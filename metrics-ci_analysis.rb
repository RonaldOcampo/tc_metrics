require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/metric/cli'
require 'socket'

class CIAnalysisGraphite < Sensu::Plugin::Metric::CLI::Graphite

  option :scheme,
    :description => "Metric naming scheme, text to prepend to metric",
    :short => "-s SCHEME",
    :long => "--scheme SCHEME",
    :default => "#{Socket.gethostname}.ci_analysis"

  def run
    Dir.chdir('/usr/local/src/tc_metrics'){
      `rm analysis_metrics_rule.txt graphite_data metrics.csv > /dev/null 2>&1`
      warning '/usr/local/src/tc_metrics/tc_metrics.rb script failed to run' unless system '/opt/sensu/embedded/bin/ruby tc_metrics.rb'
    }
    File.open("/usr/local/src/tc_metrics/graphite_data", "r").each_slice(2) do |two_lines|
      header_line = two_lines[0].strip.split(',')
      data_line = two_lines[1].strip.split(',')
      team_name = header_line[0].downcase.gsub(' ', '_')
      header_line.each_index do |index|
        next if index == 0
        
        output "#{config[:scheme]}.#{team_name}.#{header_line[index].downcase.gsub(' ', '_').gsub('/', '_')}", data_line[index]
      end
    end
    ok
  end
end
