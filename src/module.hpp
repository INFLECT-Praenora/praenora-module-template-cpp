// my-module: the capability my-module.summarize@0.1.0 (catalog/capabilities/my-module.summarize/),
// built with the module SDK's C++ adapter (praenora/sdk/module.hpp).
//
// TEMPLATE: this is the sample's logic. Replace the class with your module's; keep it in this header
// so that the unit tests (tests/module_test.cpp) can include it, and keep src/module.cpp naming it.
//
// Each tick the module receives an observation batch (input port `observations`, message type
// pmp.observation-batch@0.1.0) and, for each (series_id, variable_id) in sorted order, summarizes
// its usable observations (not missing, not censored, with a numeric value): count, mean, min, max,
// and the time and value of the latest one (on equal times, the later row). Output port `summary`
// (message type my-module.summary@0.1.0): {"time_unit", "window", "series": [...]}, the time unit
// and window copied from the batch. Parameter `min_count` (an integer of at least 1, default 1):
// series with fewer usable observations are left out.
//
// The rules every module keeps (the runtime's module developer guide, "Determinism and
// portability"): all state in the instance (so the manifest declares concurrency "instance"), no
// file I/O, no wall clock, randomness only from the step's seed, a deterministic output order (a
// std::map here), and errors as sdk::Error, which the adapter turns into a status and an error
// document. Nothing else crosses the ABI.
#ifndef MY_MODULE_MODULE_HPP
#define MY_MODULE_MODULE_HPP

#include <praenora/sdk/module.hpp>

#include <nlohmann/json.hpp>

#include <algorithm>
#include <cstdint>
#include <map>
#include <string>
#include <string_view>
#include <utility>

namespace my_module {

namespace sdk = praenora::sdk;
using nlohmann::json;

namespace detail {

// Fails the call: `code` with the message "<module name>: <what>".
[[noreturn]] inline void fail(praenora_status code, const std::string& what) {
    throw sdk::Error(code, std::string(PRAENORA_MODULE_NAME) + ": " + what);
}

// The document `text` as a JSON object; a document that is not one is INVALID_ARGUMENT.
inline json parse_object(std::string_view text, const char* what) {
    json document = json::parse(text.begin(), text.end(), nullptr, false);
    if (!document.is_object()) {
        fail(PRAENORA_STATUS_INVALID_ARGUMENT, std::string("the ") + what + " is not a JSON object");
    }
    return document;
}

// The member `key` of `object`, which must satisfy `is_type` (data of the wrong shape is
// DATA_INVALID).
template <typename Predicate>
const json& member(const json& object, const char* key, Predicate is_type, const char* what) {
    const auto found = object.find(key);
    if (found == object.end() || !is_type(*found)) {
        fail(PRAENORA_STATUS_DATA_INVALID, std::string(what) + " has no valid " + key);
    }
    return *found;
}

inline bool is_object(const json& value) { return value.is_object(); }
inline bool is_array(const json& value) { return value.is_array(); }
inline bool is_number(const json& value) { return value.is_number(); }
inline bool is_name(const json& value) {
    return value.is_string() && !value.get_ref<const std::string&>().empty();
}

// The data of input port `port` of an invocation document.
inline const json& input_data(const json& invocation, const char* port) {
    const json& inputs = member(invocation, "inputs", is_object, "the invocation");
    const auto input = inputs.find(port);
    if (input == inputs.end() || !input->is_object()) {
        fail(PRAENORA_STATUS_DATA_INVALID, std::string("the required input ") + port + " is missing");
    }
    return member(*input, "data", is_object, (std::string("input ") + port).c_str());
}

} // namespace detail

class Summarizer final : public sdk::Module {
public:
    // create(): the create document holds the step's parameters, validated against the manifest's
    // parameters_schema, with its defaults filled in (module.pmm.json.in).
    explicit Summarizer(const sdk::CreateContext& context) : host_(context.host) {
        const json create = detail::parse_object(context.create_json, "create document");
        const auto parameters = create.find("parameters");
        if (parameters == create.end() || !parameters->is_object()) {
            return;
        }
        const auto min_count = parameters->find("min_count");
        if (min_count != parameters->end()) {
            if (!min_count->is_number_integer() || min_count->get<std::int64_t>() < 1) {
                detail::fail(PRAENORA_STATUS_INVALID_ARGUMENT,
                             "min_count must be an integer of at least 1");
            }
            min_count_ = min_count->get<std::int64_t>();
        }
    }

    // initialize(): the run's fingerprint, the step's seed (run.seed) and the time base. The seed
    // is the only source of randomness a module may use; this sample draws none. A module that
    // does would seed its generator here, for example
    //   rng_.seed(document.at("run").at("seed").get<std::uint64_t>());
    void initialize(const sdk::InitializeContext& context) override {
        detail::parse_object(context.initialize_json, "initialize document");
    }

    // invoke(): one tick. Returns the result document {"outputs": {<port>: {"data": ...}}}; the
    // runtime builds the envelopes and checks the data against the port's message type.
    std::string invoke(std::string_view invocation_json) override {
        const json invocation = detail::parse_object(invocation_json, "invocation document");
        const json& batch = detail::input_data(invocation, "observations");
        const json& window = detail::member(batch, "window", detail::is_object, "the batch");
        detail::member(window, "start", detail::is_number, "the batch's window");
        detail::member(window, "end", detail::is_number, "the batch's window");
        const json& time_unit = detail::member(batch, "time_unit", detail::is_name, "the batch");
        const json& rows = detail::member(batch, "observations", detail::is_array, "the batch");

        struct Summary {
            std::int64_t count = 0;
            double sum = 0, min = 0, max = 0, last_time = 0, last_value = 0;
        };
        std::map<std::pair<std::string, std::string>, Summary> summaries;
        std::uint64_t usable = 0;
        for (const json& row : rows) {
            if (!row.is_object()) {
                detail::fail(PRAENORA_STATUS_DATA_INVALID, "an observation is not an object");
            }
            const json& series_id = detail::member(row, "series_id", detail::is_name, "a row");
            const json& variable_id = detail::member(row, "variable_id", detail::is_name, "a row");
            const double time = detail::member(row, "time", detail::is_number, "a row").get<double>();
            const auto missing = row.find("missing");
            const auto censoring = row.find("censoring");
            const auto value = row.find("value");
            if ((missing != row.end() && *missing == true) ||
                (censoring != row.end() && *censoring != "none") || value == row.end() ||
                !value->is_number()) {
                continue;
            }
            const double y = value->get<double>();
            Summary& summary = summaries[{series_id.get<std::string>(), variable_id.get<std::string>()}];
            if (summary.count == 0) {
                summary.min = summary.max = y;
            } else {
                summary.min = std::min(summary.min, y);
                summary.max = std::max(summary.max, y);
            }
            if (summary.count == 0 || time >= summary.last_time) {
                summary.last_time = time;
                summary.last_value = y;
            }
            ++summary.count;
            summary.sum += y;
            ++usable;
        }

        json series = json::array();
        for (const auto& [key, summary] : summaries) {
            if (summary.count < min_count_) {
                continue;
            }
            series.push_back({{"series_id", key.first},
                              {"variable_id", key.second},
                              {"count", summary.count},
                              {"mean", summary.sum / static_cast<double>(summary.count)},
                              {"min", summary.min},
                              {"max", summary.max},
                              {"last_time", summary.last_time},
                              {"last_value", summary.last_value}});
        }
        ++invocations_;
        observations_ += usable;
        if (host_.log_enabled(sdk::LogLevel::debug)) {
            host_.log(sdk::LogLevel::debug, std::to_string(series.size()) + " series from " +
                                                std::to_string(usable) + " usable observations");
        }

        json data = {{"time_unit", time_unit}, {"window", window}, {"series", std::move(series)}};
        return json{{"outputs", {{"summary", {{"data", std::move(data)}}}}}}.dump();
    }

    // diagnostics(): added to a failure's details (features.diagnostics in the manifest).
    std::string diagnostics() const override {
        return json{{"invocations", invocations_}, {"observations", observations_}}.dump();
    }

private:
    sdk::Host host_;
    std::int64_t min_count_ = 1;
    std::uint64_t invocations_ = 0;
    std::uint64_t observations_ = 0;
};

} // namespace my_module

#endif // MY_MODULE_MODULE_HPP
