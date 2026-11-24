// Unit tests of the module, in process: the SDK's test kit (praenora/sdk/testing.hpp) stands in for
// the runtime. FakeHost implements the host API; DirectModule calls the module's function table as
// the runtime does, with no library loaded. PRAENORA_MODULE_NAME, PRAENORA_MODULE_VERSION and
// PRAENORA_MODULE_CAPABILITIES come from tests/CMakeLists.txt, which takes them from the identity
// block of the top-level CMakeLists.txt.
//
// TEMPLATE: replace these tests with tests of your module's behavior. Keep one test of a malformed
// invocation and one of determinism; the contract checks (ctest -L contract) test the rest of the
// ABI with the library itself.
#include "module.hpp"

#include <praenora/sdk/testing.hpp>

#include <gtest/gtest.h>
#include <nlohmann/json.hpp>

#include <string>

namespace {

PRAENORA_SDK_DEFINE_MODULE_GETTER(my_module::Summarizer, module_get_api)

using nlohmann::json;
using praenora::sdk::testing::CallResult;
using praenora::sdk::testing::DirectModule;
using praenora::sdk::testing::FakeHost;

// One tick's observation batch: S01 has three usable rows, S02 one usable row and one missing
// row, and S03 only a censored row.
const json kBatch = json::parse(R"({
  "window": {"start": 0.0, "end": 1.0},
  "time_unit": "d",
  "observations": [
    {"series_id": "S01", "variable_id": "population", "time": 0.1, "value": 1.0},
    {"series_id": "S02", "variable_id": "population", "time": 0.2, "value": 10.0},
    {"series_id": "S01", "variable_id": "population", "time": 0.4, "value": 2.0},
    {"series_id": "S02", "variable_id": "population", "time": 0.5, "value": null,
     "missing": true},
    {"series_id": "S01", "variable_id": "population", "time": 0.8, "value": 4.5},
    {"series_id": "S03", "variable_id": "population", "time": 0.9, "value": null,
     "censoring": "left", "upper_limit": 3.0}
  ]
})");

std::string create_document(const json& parameters) {
    return json{{"parameters", parameters}}.dump();
}

std::string invocation(const json& batch) {
    return json{{"tick", 0},
                {"logical_time", 1.0},
                {"inputs", {{"observations", {{"data", batch}}}}}}
        .dump();
}

// The `series` of the summary that `result` holds.
json series_of(const CallResult& result) {
    return json::parse(result.output).at("outputs").at("summary").at("data").at("series");
}

TEST(Summarizer, SummarizesUsableObservations) {
    FakeHost host;
    DirectModule module(&module_get_api);
    ASSERT_EQ(module.create(host, create_document(json::object())).status, PRAENORA_STATUS_OK);
    const CallResult result = module.invoke(invocation(kBatch));
    ASSERT_EQ(result.status, PRAENORA_STATUS_OK) << result.error;

    const json data = json::parse(result.output).at("outputs").at("summary").at("data");
    EXPECT_EQ(data.at("time_unit"), "d");
    EXPECT_EQ(data.at("window"), json::parse(R"({"start": 0.0, "end": 1.0})"));
    EXPECT_EQ(data.at("series"), json::parse(R"([
      {"series_id": "S01", "variable_id": "population", "count": 3, "mean": 2.5, "min": 1.0,
       "max": 4.5, "last_time": 0.8, "last_value": 4.5},
      {"series_id": "S02", "variable_id": "population", "count": 1, "mean": 10.0, "min": 10.0,
       "max": 10.0, "last_time": 0.2, "last_value": 10.0}
    ])"));
}

TEST(Summarizer, MinCountDropsSparseSeries) {
    FakeHost host;
    DirectModule module(&module_get_api);
    ASSERT_EQ(module.create(host, create_document({{"min_count", 2}})).status, PRAENORA_STATUS_OK);
    const CallResult result = module.invoke(invocation(kBatch));
    ASSERT_EQ(result.status, PRAENORA_STATUS_OK) << result.error;
    const json series = series_of(result);
    ASSERT_EQ(series.size(), 1u);
    EXPECT_EQ(series[0].at("series_id"), "S01");
}

TEST(Summarizer, RejectsBadParameters) {
    for (const char* parameters : {R"({"min_count": 0})", R"({"min_count": 1.5})",
                                   R"({"min_count": "2"})"}) {
        FakeHost host;
        DirectModule module(&module_get_api);
        const CallResult result = module.create(host, create_document(json::parse(parameters)));
        EXPECT_EQ(result.status, PRAENORA_STATUS_INVALID_ARGUMENT) << parameters;
        EXPECT_FALSE(result.error.empty()) << parameters;
    }
}

TEST(Summarizer, RejectsMalformedInvocation) {
    FakeHost host;
    DirectModule module(&module_get_api);
    ASSERT_EQ(module.create(host, create_document(json::object())).status, PRAENORA_STATUS_OK);
    EXPECT_EQ(module.invoke("{").status, PRAENORA_STATUS_INVALID_ARGUMENT);
}

TEST(Summarizer, RejectsWrongShape) {
    FakeHost host;
    DirectModule module(&module_get_api);
    ASSERT_EQ(module.create(host, create_document(json::object())).status, PRAENORA_STATUS_OK);

    const CallResult no_input = module.invoke(R"({"tick": 0, "logical_time": 1.0, "inputs": {}})");
    EXPECT_EQ(no_input.status, PRAENORA_STATUS_DATA_INVALID);
    EXPECT_FALSE(no_input.error.empty());

    json bad_time = kBatch;
    bad_time["observations"][0]["time"] = "x";
    const CallResult bad_row = module.invoke(invocation(bad_time));
    EXPECT_EQ(bad_row.status, PRAENORA_STATUS_DATA_INVALID);
    EXPECT_FALSE(bad_row.error.empty());
}

TEST(Summarizer, IsDeterministic) {
    FakeHost host;
    DirectModule first(&module_get_api);
    DirectModule second(&module_get_api);
    ASSERT_EQ(first.create(host, create_document(json::object())).status, PRAENORA_STATUS_OK);
    ASSERT_EQ(second.create(host, create_document(json::object())).status, PRAENORA_STATUS_OK);
    const CallResult a = first.invoke(invocation(kBatch));
    const CallResult b = second.invoke(invocation(kBatch));
    ASSERT_EQ(a.status, PRAENORA_STATUS_OK) << a.error;
    EXPECT_EQ(a.output, b.output);
}

TEST(Summarizer, ReportsDiagnostics) {
    FakeHost host;
    DirectModule module(&module_get_api);
    ASSERT_EQ(module.create(host, create_document(json::object())).status, PRAENORA_STATUS_OK);
    ASSERT_EQ(module.invoke(invocation(kBatch)).status, PRAENORA_STATUS_OK);
    const CallResult diagnostics = module.diagnostics();
    ASSERT_EQ(diagnostics.status, PRAENORA_STATUS_OK);
    EXPECT_EQ(json::parse(diagnostics.output), json::parse(R"({"invocations": 1,
                                                                 "observations": 4})"));
}

} // namespace
