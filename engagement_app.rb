require 'optparse'
require 'fileutils'

require_relative './common/app_logger'
require_relative './tools/engagement_tool'

if __FILE__ == $0 #This script code is executed when running this file.

   OptionParser.new do |o|

	  #Passing in a config file.... Or you can set a bunch of parameters.
	  o.on('-a ACCOUNT', '--account', 'Account configuration file (including path) that provides OAuth settings.') { |account| $account = account }
	  o.on('-c CONFIG', '--config', 'Settings configuration file (including path) that provides API settings.') { |config| $settings = config }
	  o.on('-n NAME', '--name', 'Name for dataset, used to label output.') { |name| $name = name }

	  #endPoint (e is already used for end time), so 'p' for endPoint.
	 
	   o.on('-p POINT', '--point', 'Engagement API endpoint: totals, 28h, or historical.') { |point| $point = point }


	  #Period of search.  Defaults to end = Now(), start = Now() - 28.days.
	  o.on('-s START', '--start_date', "UTC timestamp for beginning of Engagement period.
                                         Specified as YYYYMMDD, \"YYYY-MM-DD\", ##d.") { |start_date| $start_date = start_date }
	  o.on('-e END', '--end_date', "UTC timestamp for ending of Engagement period.
                                      Specified as YYYYMMDD, \"YYYY-MM-DD\", ##d.") { |end_date| $end_date = end_date }
	  o.on('-v', '--verbose', 'When verbose, output all kinds of things, each request, most responses, etc.') { |verbose| $verbose = verbose }


	  #Help screen.
	  o.on('-h', '--help', 'Display this screen.') do
		 puts o
		 exit
	  end

	  o.parse!

   end

   #If not passed in, use some defaults.
   if ($account.nil?) then
	  $account = "./config/accounts.yaml"
   end

   if ($settings.nil?) then
	  $settings = './config/app_settings.yaml'
   end
   Client = EngagementTool.new()
   Client.verbose = true if !$verbose.nil?

   AppLogger.config_file = $settings
   AppLogger.set_config(Client.verbose)
   AppLogger.log_path = File.expand_path(AppLogger.log_path)
   AppLogger.set_logger
   AppLogger.log_info("Starting process at #{Time.now}")

   Client.set_account_config($account)
   Client.set_settings_config($settings)

   #Now that we know Engagement Type configuration, build 'top tweet' hash.
   Client.top_tweets = Client.build_top_tweets_hash if Client.max_top_tweets > 0

   #Set application attributes from command-line. These override values in the configuration file.
   Client.name = $name if !$name.nil?
   Client.endpoint = $point if !$point.nil?

   #Engagement API can have a start and end date... only relevant for historical endpoint.
   if Client.endpoint == 'historical'

	  #First, if either is not nil, ignore/rest anything in the configuration file.
	  if $start_date != nil or $end_date != nil
		 Client.start_date = nil
		 Client.end_date = nil

		 Client.start_date = $start_date
		 Client.end_date = $end_date
	  end
   end

   #---------------------------------------------------------------------------------------------------------------------

   files_to_ingest = Client.files_to_ingest?
   continue = true

   if files_to_ingest
	  Client.tweet_ids = Client.load_ids
   else
	  AppLogger.log_info "No Tweet IDs to process, quitting."
	  continue = false
   end

   if continue and Client.tweet_ids.count > 0
	  AppLogger.log_info "Have Tweet IDs, starting process at #{Time.now}"

	  continue = Client.manage_process

	  if continue
		 AppLogger.log_info "Writing Totals and Top Tweets output..."
		 output = Client.write_output
		 Client.write_results_file(output)
		 puts output if Client.verbose
	  else
		 AppLogger.log_error "Problem occurred, check logs..."
	  end
   end

   #------------------------------------------------------------------
   AppLogger.log_info("Finished at #{Time.now}")

end  
   
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
