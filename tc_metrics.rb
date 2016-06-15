require 'json'
require 'rest_client'
require 'csv'

STAGE_NAMES = {
    commit: 'Commit Stage',
    acceptance: 'Acceptance Stage',
    devqa: 'Dev/QA Stage',
    staging_mia: 'Staging Stage MIA',
    staging_atl: 'Staging Stage ATL',
    staging_phx: 'Staging Stage PHX',
    staging_tor: 'Staging Stage TOR',
    production_mia: 'Production Stage MIA',
    production_atl: 'Production Stage ATL',
    production_phx: 'Production Stage PHX',
    production_tor: 'Production Stage TOR'
}

class CIBuildMetrics
  attr_reader :build_id, :pass_count, :fail_count, :total_count

  def initialize(build_id)
    @build_id = build_id
    @pass_count = 0
    @fail_count = 0
    @total_count = 0
  end

  def to_s
    "Build Id: #{@build_id}; Pass Count: #{@pass_count}; Fail Count: #{@fail_count}; Total Count: #{@total_count}"
  end

  def gather_metrics
    begin
      url = "http://ci.mia.ucloud.int/app/rest/buildTypes/id:#{@build_id}/builds?locator=count:1000,status:SUCCESS,branch:default:any"
      # url = "http://ci.mia.ucloud.int/app/rest/buildTypes/id:#{@build_id}/builds?locator=count:1000,status:SUCCESS"
      json_response = JSON.parse(RestClient::Request.execute(method: :get, url: url, user: 'svc.teamcity.api', password: 'Te@mC!ty!ssogre@t', headers: {accept: 'application/json'}, verify_ssl: false).body)
      pass_count = json_response['count']

      url = "http://ci.mia.ucloud.int/app/rest/buildTypes/id:#{@build_id}/builds?locator=count:1000,status:FAILURE,branch:default:any"
      # url = "http://ci.mia.ucloud.int/app/rest/buildTypes/id:#{@build_id}/builds?locator=count:1000,status:FAILURE"
      json_response = JSON.parse(RestClient::Request.execute(method: :get, url: url, user: 'svc.teamcity.api', password: 'Te@mC!ty!ssogre@t', headers: {accept: 'application/json'}, verify_ssl: false).body)
      fail_count = json_response['count']

      url = "http://ci.mia.ucloud.int/app/rest/buildTypes/id:#{@build_id}/builds?locator=count:1000,status:ERROR,branch:default:any"
      # url = "http://ci.mia.ucloud.int/app/rest/buildTypes/id:#{@build_id}/builds?locator=count:1000,status:ERROR"
      json_response = JSON.parse(RestClient::Request.execute(method: :get, url: url, user: 'svc.teamcity.api', password: 'Te@mC!ty!ssogre@t', headers: {accept: 'application/json'}, verify_ssl: false).body)
      error_count = json_response['count']
    rescue => e
      puts "URL: #{url}"
      puts "Exception message: #{e.message}"
      puts "Exception backtrace: #{e.backtrace}"
      raise
    end

    @pass_count = pass_count
    @fail_count = fail_count + error_count
    @total_count = @pass_count + @fail_count
  end

  def pass_percentage
    (@pass_count.to_f / @total_count.to_f * 100).round(2)
  end

  def fail_percentage
    (@fail_count.to_f / @total_count.to_f * 100).round(2)
  end
end

class CIStageMetrics
  attr_reader :stage_name, :build_metrics_list, :pass_count, :fail_count, :total_count

  def initialize(stage_name, build_config_list = [])
    @stage_name = stage_name
    @build_metrics_list = []
    build_config_list.each do |build_id|
      @build_metrics_list << CIBuildMetrics.new(build_id)
    end
    @pass_count = 0
    @fail_count = 0
    @total_count = 0
  end

  def to_s
    "Stage Name: #{@stage_name}; Pass Count: #{@pass_count}; Fail Count: #{@fail_count}; Total Count: #{@total_count}; Build Metrics List: #{@build_metrics_list}"
  end

  def gather_metrics
    @build_metrics_list.each do |build_metrics|
      build_metrics.gather_metrics
      @pass_count += build_metrics.pass_count
      @fail_count += build_metrics.fail_count
    end
    @total_count = @pass_count + @fail_count
  end

  def pass_percentage
    (@pass_count.to_f / @total_count.to_f * 100).round(2)
  end

  def fail_percentage
    (@fail_count.to_f / @total_count.to_f * 100).round(2)
  end
end

class CIStageMetricsAnalysis
  STAGE_ACCEPTABLE_SUCCESS_RATES = {
      commit: 90,
      acceptance: 60,
      devqa: 70,
      staging_mia: 55,
      staging_atl: 55,
      staging_phx: 55,
      staging_tor: 55,
      production_mia: 90,
      production_atl: 90,
      production_phx: 90,
      production_tor: 90
  }

  @@first_team = true

  def initialize(team_name, stage_metrics_hash = {})
    @team_name = team_name
    @stage_metrics_hash = stage_metrics_hash
    @well_string = ''
    @needs_improvement_string = ''
  end

  def all_stages_defined_rule
    all_stages_defined? ? @well_string << "  - All stages defined\n" : @needs_improvement_string << "  - Stages are missing\n"
  end

  def all_stages_defined?
    [:commit, :acceptance, :devqa, :staging_atl, :staging_phx, :staging_tor, :production_atl, :production_phx, :production_tor].all? {|s| @stage_metrics_hash.key? s}
  end

  def stage_rules
    STAGE_NAMES.each do |stage_key, stage_name|
      next unless @stage_metrics_hash[stage_key]
      stage_metrics = @stage_metrics_hash[stage_key]
      if stage_metrics.pass_percentage > STAGE_ACCEPTABLE_SUCCESS_RATES[stage_key]
        @well_string << "  - #{stage_name}: aggregate stage with high success rate, above #{STAGE_ACCEPTABLE_SUCCESS_RATES[stage_key]}% success rate [#{stage_metrics.pass_percentage}%]\n"
      else
        @needs_improvement_string << "  - #{stage_name}: aggregate stage with high failure rate, below #{STAGE_ACCEPTABLE_SUCCESS_RATES[stage_key]}% success rate [#{stage_metrics.pass_percentage}%]\n"
      end

      first_well_build = first_improvement_build = true
      stage_metrics.build_metrics_list.each do |build_metrics|
        if build_metrics.pass_percentage > STAGE_ACCEPTABLE_SUCCESS_RATES[stage_key]
          if first_well_build
            @well_string << "  - #{stage_name} builds with high success rate, above #{STAGE_ACCEPTABLE_SUCCESS_RATES[stage_key]}% success rate\n"
            first_well_build = false
          end
          @well_string << "    - Build id: #{build_metrics.build_id} [#{build_metrics.pass_percentage}%]\n"
        else
          if first_improvement_build
            @needs_improvement_string << "  - #{stage_name} builds with high failure rate, below #{STAGE_ACCEPTABLE_SUCCESS_RATES[stage_key]}% success rate\n"
            first_improvement_build = false
          end
          @needs_improvement_string << "    - Build id: #{build_metrics.build_id} [#{build_metrics.pass_percentage}%]\n"
        end
      end
    end
  end

  def staging_vs_production_rule
    {staging_mia: :production_mia, staging_atl: :production_atl, staging_phx: :production_phx, staging_tor: :production_tor}.each do |staging_key, production_key|
      if @stage_metrics_hash[staging_key] && @stage_metrics_hash[production_key]
        if @stage_metrics_hash[staging_key].total_count >= @stage_metrics_hash[production_key].total_count
          @well_string << "  - #{STAGE_NAMES[staging_key]} aggregate build counts greater or equal than #{STAGE_NAMES[production_key]} build counts [#{@stage_metrics_hash[staging_key].total_count} - #{@stage_metrics_hash[production_key].total_count}]\n"
        else
          @needs_improvement_string << "  - #{STAGE_NAMES[staging_key]} aggregate build counts should be greater or equal than #{STAGE_NAMES[production_key]} build counts [#{@stage_metrics_hash[staging_key].total_count} - #{@stage_metrics_hash[production_key].total_count}]\n"
        end
      end
    end
  end

  def generate_metrics_analysis_file
    all_stages_defined_rule
    stage_rules
    staging_vs_production_rule

    File.open('analysis_metrics_rule.txt', 'a+') do |f|
      if @@first_team
        f.puts('NOTE: TC keeps build data for the last 35 days. Keeps artifacts for 5 days from last build and last 5 successful builds')
        f.puts
        @@first_team = false
      end
      f.puts("Team Name: #{@team_name}")
      f.puts('Well')
      f.puts(@well_string) unless @well_string == ''
      f.puts('Needs Improvement')
      f.puts(@needs_improvement_string) unless @needs_improvement_string == ''
      f.puts
      f.puts
    end
  end
end

def gather_metrics_for_team(team_name, build_config_list_per_stage)
  stage_data_pass = {team_name => 'Pass'}
  stage_data_fail = {team_name => 'Fail'}
  stage_options = [team_name]

  build_data_pass = {team_name => 'Pass'}
  build_data_fail = {team_name => 'Fail'}
  build_options = [team_name]
  build_stage_options = [team_name]

  graphite_data_pass = {team_name => 'Pass'}

  stage_metrics_hash = {}

  STAGE_NAMES.each do |stage_key, stage_name|
    next unless build_config_list_per_stage[stage_key]
    stage_metrics = CIStageMetrics.new(stage_name, build_config_list_per_stage[stage_key])
    stage_metrics.gather_metrics

    stage_metrics_hash[stage_key] = stage_metrics

    stage_data_pass[stage_metrics.stage_name] = "#{stage_metrics.pass_count} - #{stage_metrics.pass_percentage}%"
    stage_data_fail[stage_metrics.stage_name] = "#{stage_metrics.fail_count} - #{stage_metrics.fail_percentage}%"
    stage_options << stage_metrics.stage_name

    graphite_data_pass[stage_metrics.stage_name] = stage_metrics.pass_percentage

    stage_metrics.build_metrics_list.each do |build_metrics|
      build_data_pass[build_metrics.build_id] = "#{build_metrics.pass_count} - #{build_metrics.pass_percentage}%"
      build_data_fail[build_metrics.build_id] = "#{build_metrics.fail_count} - #{build_metrics.fail_percentage}%"
      build_stage_options << stage_name
      build_options << build_metrics.build_id
    end
  end

  CSV.open('metrics.csv', 'a+') do |csv|
    csv << stage_options
    csv << stage_data_pass.values
    csv << stage_data_fail.values
    csv << []
    csv << build_stage_options
    csv << build_options
    csv << build_data_pass.values
    csv << build_data_fail.values
    csv << []
    csv << []
  end

  CSV.open('graphite_data', 'a+') do |csv|
    csv << stage_options
    csv << graphite_data_pass.values
  end

  stage_metrics_analysis = CIStageMetricsAnalysis.new(team_name, stage_metrics_hash)
  stage_metrics_analysis.generate_metrics_analysis_file
end

# template_stages = {
#     commit: [''],
#     acceptance: [''],
#     devqa: [''],
#     staging_mia: [''],
#     staging_atl: [''],
#     staging_phx: [''],
#     staging_tor: [''],
#     production_mia: [''],
#     production_atl: [''],
#     production_phx: [''],
#     production_tor: [''],
# }
# gather_metrics_for_team 'TEMPLATE', template_stages

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

rec_stages = {
    commit: ['bt333', 'NRECCommitStage_2EQuestUnitTests', 'NRECCommitStage_11UnitTests'],
    acceptance: ['NREC_ATC_1TestDeployment', 'NREC_ATC_15IntegrationTests', 'NREC_ATC_22EQuestIntegrationTests', 'NREC_ATC_20Candidate', 'NREC_ATC_201CandidateFindsOpportunity', 'NREC_ATC_2011CandidateFindsOpportunity', 'NREC_ATC_202CandidateReferenceRecommends', 'NREC_ATC_203CandidateViewsAndManagesPresence', 'NREC_ATC_2031CandidateViewsAndManagesPresence', 'NREC_ATC_2032CandidateViewsAndManagesPresence', 'NREC_ATC_204CandidateVisualizesAndManagesReferences', 'NREC_ATC_2041CandidateVisualizesAndManagesReferences', 'NREC_ATC_205Opportunity', 'NREC_ATC_214', 'NREC_ATC_30ClusterSetttingsIsolated', 'NREC_ATC_41IdentityIntegrationTests'],
    devqa: ['bt181', 'NrecDemoEnvironments_1CreateAllInTwo', 'bt272', 'bt548', 'NrecDemoEnvironments_SimulateProductionUpgrade'],
    staging_atl: ['bt178', 'NrecAtlantaStagingEnvironments_SimulateProductionUpgrade'],
    staging_phx: ['bt459', 'NrecPhoenixStagingEnvironments_SimulateProductionUpgrade'],
    staging_tor: ['bt506', 'NrecTorontoStagingEnvironments_SimulateProductionUpgrade'],
    production_atl: ['NrecAtlantaProductionEnvironments_CreateForUpgrade', 'NrecAtlantaProductionEnvironments_2UpgradeToExisting', 'bt188', 'NrecAtlantaProductionEnvironments_SimulateProductionUpgrade'],
    production_phx: ['NrecPhoenixProductionEnvironments_CreateForUpgrade', 'NrecPhoenixProductionEnvironments_2UpgradeToExisting', 'bt468', 'NrecPhoenixProductionEnvironments_SimulateProductionUpgrade'],
    production_tor: ['NRECTorontoProductionEnvironments_1CreateForUpgrade', 'NRECTorontoProductionEnvironments_2UpgradeToExisting', 'bt512', 'NRECTorontoProductionEnvironments_SimulateProductionUpgrade'],
}
gather_metrics_for_team 'REC', rec_stages

rst_identityV1_stages = {
    commit: ['NTESCommitStage_1bBuildAndUnitTest'],
    acceptance: ['Tes_2IdentityAcceptanceTests_2SmokeTests', 'Tes_2IdentityAcceptanceTests_2uccNewContractTests', 'Tes_2IdentityAcceptanceTests_2FunctionalUiTests', 'Tes_2IdentityAcceptanceTests_2IntegrationTests', 'Tes_2IdentityAcceptanceTests_3NightlyPerformanceTests'],
    devqa: ['Tes_3IdentityDemoEnvironments_31Create', 'Tes_4IdentityScaledOutEnvironments_Create', 'Tes_4IdentityScaledOutEnvironments_UpgradeAppServers'],
    staging_atl: ['NTESAtlantaStagingEnvironments_Create', 'NTESAtlantaStagingEnvironments_UpgradeAppServers'],
    staging_tor: ['Tes_4Staging_4identityUccTorontoStagingEnvironments_Create', 'Tes_4Staging_4identityUccTorontoStagingEnvironments_UpgradeAppServers'],
    production_atl: ['NTESAtlantaProductionEnvironments_Create', 'NTESAtlantaProductionEnvironments_UpgradeAppServers'],
    production_tor: ['Tes_5Production_5identityUccTorontoProductionEnvironments_Create', 'Tes_5Production_5identityUccTorontoProductionEnvironments_UpgradeAppServers'],
}
gather_metrics_for_team 'RST Identity V1', rst_identityV1_stages

rst_ucc_stages = {
    commit: ['NADMCommitStage_1BuildAndUnitTest'],
    acceptance: ['Ssd_UccBetaAcceptanceTests_2SmokeTests', 'Ssd_UccBetaAcceptanceTests_22SetupProtractorUiTests', 'Ssd_UccBetaAcceptanceTests_222RunFunctionalPerformanceTests', 'Ssd_UccBetaAcceptanceTests_2ContractTests', 'Ssd_UccBetaAcceptanceTests_25onbContractTests'],
    devqa: ['RST_Ucc_3uccTestEnvironments_AdmDemoCreate', 'Sdd_AdmDemo_AdmDemoCreate', 'Sdd_AdmDemo_UccDemoUpgrade', 'Sdd_AdmDemo_33UpdateApplicationConfiguration'],
    staging_atl: ['Ssd_UccStaging_AdmDemoCreate', 'Ssd_UccStaging_UccStaginUpgrade'],
    staging_tor: ['RST_Ucc_4Staging_4uccTorontoStagingEnvironments_AdmDemoCreate', 'RST_Ucc_4Staging_4uccTorontoStagingEnvironments_UccStaginUpgrade'],
    production_atl: ['Ssd_5uccProduction_AdmDemoCreate', 'Ssd_5uccProduction_53ProductionUpgrade', 'Ssd_5uccProduction_43UpdateApplicationConfiguration'],
    production_tor: ['RST_Ucc_5Production_5uccTorontoProductionEnvironments_AdmDemoCreate', 'RST_Ucc_5Production_5uccTorontoProductionEnvironments_53ProductionUpgrade'],
}
gather_metrics_for_team 'RST UCC', rst_ucc_stages

rst_dms_stages = {
    commit: ['DMS_Product_CommitStage_11BuildAndUnitTest'],
    acceptance: ['DMS_Services_2AcceptanceTests_21ContractTests', 'DMS_Services_2dmsAcceptanceTests_28RunReconciliation'],
    devqa: ['DMS_Services_3DemoEnvironments_31Cre', 'DMS_Services_4MiamiTestingEnvironments_41Create', 'DMS_Services_4MiamiTestingEnvironments_43Upgrade'],
    staging_atl: ['DMS_Services_5AtlantaStagingEnvironments_51Create', 'DMS_Services_5AtlantaStagingEnvironments_53Upgrade'],
    staging_phx: ['DMS_Services_5PhoenixStagingEnvironments_51Create', 'DMS_Services_5PhoenixStagingEnvironments_53Upgrade'],
    staging_tor: ['DMS_Services_Staging_5TorontoStagingEnvironments_51Create', 'DMS_Services_Staging_5TorontoStagingEnvironments_53Upgrade'],
    production_atl: ['DMS_Services_6AtlantaProductionEnvironments_61Create', 'DMS_Services_6AtlantaProductionEnvironments_63Upgrade'],
    production_phx: ['DMS_Services_7PhoenixProductionEnvironments_31Cre', 'DMS_Services_7PhoenixProductionEnvironments_33Upgrade'],
    production_tor: ['DMS_Services_6Production_6TorontoProductionEnvironments_61Create', 'DMS_Services_6Production_6TorontoProductionEnvironments_63Upgrade'],
}
gather_metrics_for_team 'RST DMS', rst_dms_stages

aca_stages = {
    commit: ['ACAFiling_CommitStage_BuildAndUnitTest'],
    acceptance: ['ACAFiling_AcceptanceStage_NunitAcceptanceTest', 'ACAFiling_AcceptanceStage_NunitIntegrationTest'],
    devqa: ['ACAFiling_DevSandbox_CreateEnvironment', 'ACAFiling_PsrSandbox_CreateEnvironment', 'ACAFiling_3ReleaseCandidateUat_CreateOrUpgradeEnvironment'],
    staging_atl: ['ACAFiling_Staging_CreateOrUpgradeEnvironment'],
    production_atl: ['ACAFiling_Prodution_CreateOrUpgradeEnvironment'],
}
gather_metrics_for_team 'ACA', aca_stages

hoth_dns_api_stages = {
    commit: ['ucp_HothDnsApi_CommitStage_BuildAndUnitTest'],
    acceptance: ['ucp_HothDnsApi_AcceptanceStage_FunctionalTest', 'ucp_HothDnsApi_AcceptanceStage_AcceptanceTest', 'ucp_HothDnsApi_AcceptanceStage_PerformanceTest', 'ucp_HothDnsApi_AcceptanceStage_SmokeTest'],
    devqa: ['ucp_HothDnsApi_DevQa_Create'],
    staging_mia: ['ucp_HothDnsApi_41StagingMi_Create'],
    staging_atl: ['ucp_HothDnsApi_42StagingAtl_Create'],
    staging_phx: ['ucp_HothDnsApi_43StagingPhx_Create'],
    staging_tor: ['ucp_HothDnsApi_44StagingTo_Create'],
    production_mia: ['ucp_HothDnsApi_51ProdMia_Create'],
    production_atl: ['ucp_HothDnsApi_52ProductionAtl_Create'],
    production_phx: ['ucp_HothDnsApi_53ProductionPhx_Create'],
    production_tor: ['ucp_HothDnsApi_54ProductioTor_ACreate'],
}
gather_metrics_for_team 'Hoth DNS API', hoth_dns_api_stages