require 'json'
require 'rest_client'
require 'table_print'

class CIStageMetrics
  attr_reader :pass_count, :fail_count

  def initialize(stage_name, build_config_list = [])
    @stage_name = stage_name
    @build_config_list = build_config_list
    @pass_count = 0
    @fail_count = 0
  end

  def to_s
    "Stage Name: #{@stage_name}; Pass Count: #{@pass_count}; Fail Count: #{@fail_count}; Build Config List: #{@build_config_list}"
  end

  def gather_metrics
    @build_config_list.each do |build_id|
      json_response = JSON.parse(RestClient::Request.execute(method: :get, url: "http://ci.mia.ucloud.int/app/rest/buildTypes/id:#{build_id}/builds?locator=count:1000,status:SUCCESS", user: 'ronaldo', password: 'PASSWORD', headers: {accept: 'application/json'}).body)
      pass_count = json_response['count']

      json_response = JSON.parse(RestClient::Request.execute(method: :get, url: "http://ci.mia.ucloud.int/app/rest/buildTypes/id:#{build_id}/builds?locator=count:1000,status:FAILURE", user: 'ronaldo', password: 'PASSWORD', headers: {accept: 'application/json'}).body)
      fail_count = json_response['count']

      json_response = JSON.parse(RestClient::Request.execute(method: :get, url: "http://ci.mia.ucloud.int/app/rest/buildTypes/id:#{build_id}/builds?locator=count:1000,status:ERROR", user: 'ronaldo', password: 'PASSWORD', headers: {accept: 'application/json'}).body)
      error_count = json_response['count']

      @pass_count += pass_count
      @fail_count += fail_count + error_count
    end
  end

  def pass_percentage
    (@pass_count.to_f / (@pass_count.to_f + @fail_count.to_f) * 100).round(2)
  end

  def fail_percentage
    (@fail_count.to_f / (@pass_count.to_f + @fail_count.to_f) * 100).round(2)
  end
end

def gather_metrics_for_team(team_name,build_config_list_per_stage)
  commit = CIStageMetrics.new('Commit Stage', build_config_list_per_stage[:commit])
  commit.gather_metrics
  puts commit.to_s

  acceptance = CIStageMetrics.new('Acceptance Stage', build_config_list_per_stage[:acceptance])
  acceptance.gather_metrics
  puts acceptance.to_s

  devqa = CIStageMetrics.new('Dev/QA Stage', build_config_list_per_stage[:devqa])
  devqa.gather_metrics
  puts devqa.to_s

  staging_atl = CIStageMetrics.new('Staging Stage ATL', build_config_list_per_stage[:staging_atl])
  staging_atl.gather_metrics
  puts staging_atl.to_s

  staging_phx = CIStageMetrics.new('Staging Stage PHX', build_config_list_per_stage[:staging_phx])
  staging_phx.gather_metrics
  puts staging_phx.to_s

  staging_tor = CIStageMetrics.new('Staging Stage TOR', build_config_list_per_stage[:staging_tor])
  staging_tor.gather_metrics
  puts staging_tor.to_s

  production_atl = CIStageMetrics.new('Production Stage ATL', build_config_list_per_stage[:production_atl])
  production_atl.gather_metrics
  puts production_atl.to_s

  production_phx = CIStageMetrics.new('Production Stage PHX', build_config_list_per_stage[:production_phx])
  production_phx.gather_metrics
  puts production_phx.to_s

  production_tor = CIStageMetrics.new('Production Stage TOR', build_config_list_per_stage[:production_tor])
  production_tor.gather_metrics
  puts production_tor.to_s

  data = [{team_name => 'Pass',
           'Commit Stage' => "#{commit.pass_count} - #{commit.pass_percentage}%",
           'Acceptance Stage' => "#{acceptance.pass_count} - #{acceptance.pass_percentage}%",
           'Dev/QA Stage' => "#{devqa.pass_count} - #{devqa.pass_percentage}%",
           'Staging Stage ATL' => "#{staging_atl.pass_count} - #{staging_atl.pass_percentage}%",
           'Staging Stage PHX' => "#{staging_phx.pass_count} - #{staging_phx.pass_percentage}%",
           'Staging Stage TOR' => "#{staging_tor.pass_count} - #{staging_tor.pass_percentage}%",
           'Production Stage ATL' => "#{production_atl.pass_count} - #{production_atl.pass_percentage}%",
           'Production Stage PHX' => "#{production_phx.pass_count} - #{production_phx.pass_percentage}%",
           'Production Stage TOR' => "#{production_tor.pass_count} - #{production_tor.pass_percentage}%"
          },
          {team_name => 'Fail',
           'Commit Stage' => "#{commit.fail_count} - #{commit.fail_percentage}%",
           'Acceptance Stage' => "#{acceptance.fail_count} - #{acceptance.fail_percentage}%",
           'Dev/QA Stage' => "#{devqa.fail_count} - #{devqa.fail_percentage}%",
           'Staging Stage ATL' => "#{staging_atl.fail_count} - #{staging_atl.fail_percentage}%",
           'Staging Stage PHX' => "#{staging_phx.fail_count} - #{staging_phx.fail_percentage}%",
           'Staging Stage TOR' => "#{staging_tor.fail_count} - #{staging_tor.fail_percentage}%",
           'Production Stage ATL' => "#{production_atl.fail_count} - #{production_atl.fail_percentage}%",
           'Production Stage PHX' => "#{production_phx.fail_count} - #{production_phx.fail_percentage}%",
           'Production Stage TOR' => "#{production_tor.fail_count} - #{production_tor.fail_percentage}%"
          }]

  puts
  tp data, team_name, 'Commit Stage', 'Acceptance Stage', 'Dev/QA Stage', 'Staging Stage ATL', 'Staging Stage PHX', 'Staging Stage TOR', 'Production Stage ATL', 'Production Stage PHX', 'Production Stage TOR'
  puts
end

onb_stages = {
    commit: ['NONB_NONBCommitStageSpade_BuildAndUnitTest'],
    acceptance: ['NONB_NONBAcceptanceTestsSpade_EnvironmentSmokeTestAllTogglesOn', 'NONB_NONBAcceptanceTestsSpade_EnvironmentSmokeTestProductionToggles', 'NONB_FunctionalTestsAllTogglesOn', 'NONB_NONBAcceptanceTestsSpade_FunctionalTestsProductionToggles', 'NONB_NONBAcceptanceTestsSpade_IntegrationAndSpecificationTests'],
    devqa: ['NONB_NONBDemoEnvironmentsSpade_Create', 'NONB_CreateDailyPsrEnvironment', 'NONB_NONBDemoEnvironmentsSpade_CreateDailySandbox', 'NONB_NONBDemoEnvironmentsSpade_CreateMultiNode', 'NONB_NONBDemoEnvironmentsSpade_SimulateUpgrade', 'NONB_NONBDemoEnvironmentsSpade_UpgradeDemoEnvironment'],
    staging_atl: ['NONB_NONBAtlantaStagingEnvironmentsSpade_Create', 'NONB_NONBAtlantaStagingEnvironmentsSpade_SimulateUpgrade', 'NONB_NONBAtlantaStagingEnvironmentsSpade_UpgradeDemoEnvironment_2'],
    staging_phx: ['NONB_NONBPhoenixStagingEnvironmentsSpade_Create', 'NONB_NONBPhoenixStagingEnvironmentsSpade_SimulateUpgrade', 'NONB_NONBPhoenixStagingEnvironmentsSpade_UpgradeDemoEnvironment2'],
    staging_tor: ['NONB_NONBTorontoStagingEnvironmentsSpade_Create', 'NONB_NONBTorontoStagingEnvironmentsSpade_SimulateUpgrade', 'NONB_NONBTorontoStagingEnvironmentsSpade_UpgradeDemoEnvironment2'],
    production_atl: ['NONB_NONBAtlantaProductionEnvironmentsSpade_Create', 'NONB_AtlantaProduction_SimulateUpgrade', 'NONB_NONBAtlantaProductionEnvironmentsSpade_UpgradeDemoEnvironment'],
    production_phx: ['NONB_NONBPhoenixProductionEnvironmentsSpade_Create', 'NONB_NONBPhoenixProductionEnvironmentsSpade_SimulateUpgrade', 'NONB_NONBPhoenixProductionEnvironmentsSpade_UpgradeDemoEnvironment'],
    production_tor: ['NONB_NONBTProductionEnvironmentsSpade_Create', 'NONB_TorontoProduction_SimulateUpgrade', 'NONB_NONBTProductionEnvironmentsSpade_UpgradeDemoEnvironment'],
}
gather_metrics_for_team 'ONB', onb_stages

pcal_stages = {
    commit: ['bt102'],
    acceptance: ['bt238', 'NPCALAcceptanceTests_1RunUiTestsExpressionBuilderCalcRuleAndUsability', 'NPCALAcceptanceTests_1RunUiTestsExpressionBuilderEditor', 'NPCALAcceptanceTests_1RunUiTestsExpressionBuilderFunctionsAndVariables', 'bt601', 'bt599', 'bt126', 'NPCALAcceptanceTests_1RunUnitTests'],
    devqa: ['NPCALDevPlayground_1Create', 'NPCALDemoEnvironments_2CreateUCloudFromMaster', 'NPCALDemoEnvironments_3CreateUCloudMultiNodeAskFirstUseTheOtherCreate', 'PerfMulti000'],
    staging_atl: ['NPCALStagingEnvironments_2Create'],
    staging_phx: ['NPCALPhoenixStagingEnvironments_2Create'],
    staging_tor: ['NPCAL_NPCALTorontoStagingEnvironments_2Create'],
    production_atl: ['NPCAL_NPCALAtlantaProductionEnvironments_2Create'],
    production_phx: ['NPCAL_NPCALPhoenixProductionEnvironments_2Create'],
    production_tor: ['NPCAL_NPCALTorontoProductionEnvironments_2Create'],
}
gather_metrics_for_team 'PCAL', pcal_stages