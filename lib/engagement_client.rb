require 'json'
require 'yaml'
require 'csv'
require 'zlib'

require 'oauth'
require_relative '../common/insights_utils'
require_relative '../common/app_logger'

class EngagementClient

   MAX_TWEETS_PER_REQUEST_TOTALS = 250
   MAX_TWEETS_PER_REQUEST_28HR = 25
   MAX_TWEETS_PER_REQUEST_HISTORICAL = 25
   MAX_HISTORICAL_DAYS = 28
   TOTALS_ENGAGEMENT_TYPES = ['retweets', 'favorites', 'replies']
   HISTORICAL_METRIC_DATE_LIMIT = '2015-09-01' #Before which ['retweets', 'favorites', 'replies'] are not available.

   REQUEST_SLEEP_IN_SECONDS = 10 #Sleep this long with hitting request rate limit.

   @@request_num

   attr_accessor :keys,
				 :api,
				 :endpoint,
				 :inbox, #files containing Gnip output (HPT, Search).

				 :name, #Session name.
				 :engagement_types,
				 :groupings,

				 :tweet_ids, #Corpus of Tweets we are processing.
				 :tweets_of_interest, #an array of Tweet ids loaded in 25/250 at a time.
				 :num_requests,
				 :process_duration,

				 :start_date, :end_date, #Optional, API 'historical' endpoint defaults to last 28 days.

				 :outbox, #Where any API outputs are written.
				 :name_based_folders,
				 :save_ids,
				 :save_api_responses,

				 :base_url,
				 :uri_path,

				 :rate_limit_requests,
				 :rate_limit_seconds,

				 :top_tweets,
				 :max_top_tweets,

				 :utils,
				 :verbose

   def initialize

	  @verbose = false
	  @utils = InsightsUtils.new(@verbose)

	  #Total 'corpus' of Tweet IDs to process.
	  @tweet_ids = {}
	  @tweet_ids['tweet_ids'] = []
	  #Tweets passed into a EngagementAPI request, subject to MAX_TWEETS_PER_REQUEST.
	  @tweets_of_interest = []
	  @num_requests = 0
	  @process_duration = 0

	  #Simple structure for storing top tweets.
	  @top_tweets = {}
	  @max_top_tweets = 10

	  @name = ''
	  @engagement_types = []
	  @groupings = []

	  @save_api_responses = true

	  @@request_num = 0 #Used to count requests for session summary.
	  @outbox = './output'
	  @name_based_folders = false

	  @keys = {}

	  @base_url = 'https://data-api.twitter.com'
	  @endpoint = 'totals'
	  @uri_path = "/insights/engagement/#{@endpoint}"
	  @rate_limit_requests = 6
	  @rate_limit_seconds = 60
   end

   def set_account_config(file)

	  begin
		 keys = YAML::load_file(file)
		 @keys = keys['engagement_api']
	  rescue
		 puts "Error trying to load account settings. Could not parse account YAML file. Quitting."
		 @keys = nil
	  end
   end

   def set_settings_config(file)

	  begin
		 settings = {}
		 settings = YAML::load_file(file)
	  rescue
		 puts "Error trying to load app settings. Could not parse settings YAML file. Quitting."
		 settings = nil
	  end

	  #Now parse contents and load separate attributes.

	  begin

		 @name = settings['engagement_settings']['name']

		 @endpoint = settings['engagement_settings']['endpoint'] #What endpoint are we hitting?

		 @inbox = settings['engagement_settings']['inbox'] #Where the Tweets are coming from.
		 @outbox = settings['engagement_settings']['outbox']
		 @name_based_folders = settings['engagement_settings']['name_based_folders']

		 @rate_limit_requests = settings['engagement_settings']['rate_limit_requests']
		 @rate_limit_seconds = settings['engagement_settings']['rate_limit_seconds']

		 @max_top_tweets = settings['engagement_settings']['max_top_tweets']

		 @start_date = settings['engagement_settings']['start']
		 @end_date = settings['engagement_settings']['end']

		 @engagement_types = settings['engagement_types']
		 @groupings = settings['engagement_groupings']

		 @verbose = settings['engagement_settings']['verbose']

		 @save_ids = settings['engagement_settings']['save_ids']
		 @request_resources = settings['engagement_settings']['request_resources']
		 @save_api_responses = settings['engagement_settings']['save_api_responses']

	  rescue
		 puts "Error loading settings. Check settings."
	  end

	  #Create folders if they do not exist.
	  if (!File.exist?(@inbox))
		 Dir.mkdir(@inbox)
	  end

	  if (!File.exist?("#{@inbox}/processed"))
		 Dir.mkdir("#{@inbox}/processed")
	  end

	  if (!File.exist?(@outbox))
		 Dir.mkdir(@outbox)
	  end

	  if @name_based_folders

		 if (!File.exist?("#{@outbox}/#{@name}"))
			Dir.mkdir("#{@outbox}/#{@name}")
		 end

		 if (!File.exist?("#{@outbox}/#{@name}/metrics"))
			Dir.mkdir("#{@outbox}/#{@name}/metrics")
		 end

		 @outbox = "#{@outbox}/#{@name}"

	  else
		 if (!File.exist?("#{@outbox}/metrics"))
			Dir.mkdir("#{@outbox}/metrics")
		 end
	  end

   end

   def get_api_access

	  consumer = OAuth::Consumer.new(@keys['consumer_key'], @keys['consumer_secret'], {:site => @base_url})
	  token = {:oauth_token => @keys['access_token'],
			   :oauth_token_secret => @keys['access_token_secret']
	  }

	  @api = OAuth::AccessToken.from_hash(consumer, token)

   end

   def handle_response_error(result)

	  AppLogger.log_error "ERROR. Response code: #{result.code} | Message: #{result.message} | Server says: #{result.body}"
   end

   def make_post_request(uri_path, request)

	  begin

		 get_api_access if @api.nil? #token timeout?

		 @@request_num += 1
		 AppLogger.log_info "Client making API request: #{request[0..80]}"
		 result = @api.post(uri_path, request, {"content-type" => "application/json"})

		 if result.code.to_i > 201
			handle_response_error(result)
		 end

		 result.body
	  rescue
		 AppLogger.log_error "Error making POST request. "
	  end
   end

=begin
	  {top_tweets[]: { "type", tweets[{"id", "count"}] }
	  totals[]: { "type", "count"}] }
	  }
=end

=begin | By Tweet results that determine Top tweets.
{
    "by_tweet_type": {
        "657814465384071168": {
            "engagements": "0",
            "impressions": "24884"
        },
        "658837741438799873": {
            "engagements": "0",
            "impressions": "24905"
        }
    }
}
=end

   #Dynamically build data structure based on configured Engagement Types.
   def build_top_tweets_hash

	  tweet = {}
	  tweet['id'] = "0"
	  tweet['count'] = 0

	  top_tweets["top_tweets"] = []

	  #add a hash for every 'true' @engagement_types
	  @engagement_types.each { |engagement_type|

		 if (@endpoint != 'totals' and engagement_type[1]) or
			 (@endpoint == 'totals' and TOTALS_ENGAGEMENT_TYPES.include?(engagement_type[0]) and engagement_type[1])

			engagement_group = {}
			engagement_group['type'] = engagement_type[0];

			#add a hash for every top tweet .
			engagement_group['tweets'] = Array.new(@max_top_tweets, tweet)

			top_tweets["top_tweets"] << engagement_group
		 end
	  }

	  top_tweets["totals"] = []

	  #add a hash for every 'true' @engagement_types
	  @engagement_types.each { |engagement_type|

		 if (@endpoint != 'totals' and engagement_type[1]) or
			 (@endpoint == 'totals' and TOTALS_ENGAGEMENT_TYPES.include?(engagement_type[0]) and engagement_type[1])

			engagement_group = {}
			engagement_group['type'] = engagement_type[0];

			engagement_group['count'] = 0

			top_tweets["totals"] << engagement_group
		 end
	  }

	  top_tweets

   end

   def sort_top_tweets(top_tweets = nil)
	  top_tweets = @top_tweets if top_tweets.nil?

	  top_tweets['top_tweets'].each { |top_tweets_by_type|
		 array = top_tweets_by_type['tweets']
		 array.sort_by! { |hsh| hsh['count'] }.reverse!
	  }

	  top_tweets
   end

   def top_tweet?(type, count, top_tweets = nil)

	  top_tweets = @top_tweets if top_tweets.nil?

	  top_tweets_hash = top_tweets['top_tweets']

	  top_tweets_hash.each { |top_tweets_type|

		 if top_tweets_type['type'] == type

			top_tweets_type['tweets'].each { |tweet|

			   tweet_count = tweet['count'].to_i

			   if tweet_count < count.to_i
				  return true
			   end
			}
		 end
	  }

	  false

   end

   def top_tweets_trim(type, top_tweets = nil)
	  top_tweets = @top_tweets if top_tweets.nil?
	  tweet_to_delete = {}

	  #add to array
	  top_tweets['top_tweets'].each { |top_tweets_by_type|
		 if top_tweets_by_type['type'] == type

			count_min = 100_000_000_000

			top_tweets_by_type['tweets'].each { |tweet|

			   if tweet['count'].to_i < count_min
				  count_min = tweet['count'].to_i
				  tweet_to_delete = {}
				  tweet_to_delete['id'] = tweet['id']
				  tweet_to_delete['count'] = tweet['count'].to_i
			   end
			}

			if not tweet_to_delete.nil?

			   array = top_tweets_by_type['tweets']

			   array.delete_at(array.index(tweet_to_delete) || array)

			   #top_tweets_by_type['tweets'].delete_at(top_tweets_by_type['tweets'].index(tweet_to_delete) || top_tweets_by_type['tweets'])
			end
		 end

	  }
   end

   def top_tweets_add(type, count, tweet_id, top_tweets = nil)

	  top_tweets = @top_tweets if top_tweets.nil?

	  #add to array
	  top_tweets['top_tweets'].each { |top_tweets_by_type|

		 if top_tweets_by_type['type'] == type

			top_tweet = {}
			top_tweet['id'] = tweet_id
			top_tweet['count'] = count.to_i

			top_tweets_by_type['tweets'] << top_tweet
		 end

	  }

	  top_tweets_trim(type, top_tweets)

   end

   def check_top_tweets(type, tweet, top_tweets = nil)

	  top_tweets = @top_tweets if top_tweets.nil?

	  if top_tweet?(type, count, top_tweets)
		 top_tweets_add(type, tweet_id, count, top_tweets)
	  end

   end

   def manage_totals(type, count, top_tweets)

	  top_tweets = @top_tweets if top_tweets.nil?

	  totals_hash = top_tweets['totals']

	  totals_hash.each { |totals_by_type|

		 if totals_by_type['type'] == type
			totals_by_type['count'] += count.to_i
		 end
	  }

   end

   def manage_top_tweets(results, top_tweets = nil)

	  top_tweets = @top_tweets if top_tweets.nil?

	  top_engagement_types = []

	  @engagement_types.each { |type, turned_on|
		 if turned_on
			top_engagement_types << type
		 end
	  }

	  #Transverse the "by Tweets" section
	  tweet_results = results['by_tweet_type']

	  if tweet_results.nil?
		 AppLogger.log_error "Managing Top Tweets, but not finding 'by_tweet_type' in Engagement Groupings..."
	  end

	  tweet_results.each { |tweet_id, tweet_engagements|

		 tweet_engagements.each { |engagement_type, count|

			top_engagement_types.each { |type|
			   if type == engagement_type
				  if top_tweet?(type, count, top_tweets)
					 top_tweets_add(type, count, tweet_id, top_tweets)
				  end

				  #Add results to totals.
				  manage_totals(type, count, top_tweets) if count.to_i > 0

			   end
			}
		 }
	  }

   end
   
   def write_output(top_tweets = nil)

	  top_tweets = @top_tweets if top_tweets.nil?
	  
	  extra_spaces = '          '

	  #Write results to a string.
	  output = ''
	  
	  output = "Engagement API Results "
	  if @name != nil 
	  	output += "for #{@name} dataset."
	  end
	  output += "\n \nNumber of Tweets: \t #{@tweet_ids.length} \n \n"
	  output += "Engagement Type #{extra_spaces} \t Total \n"
	  
	  if @max_top_tweets > 0
	  
		 top_tweets["totals"].each { |totals_by_type|
   
			if @endpoint != 'totals' or (@endpoint == 'totals' and TOTALS_ENGAGEMENT_TYPES.include?(totals_by_type['type']))
			   output += "#{totals_by_type['type'].capitalize} #{extra_spaces}\t #{extra_spaces} #{totals_by_type['count'].to_s} \n"
			end
		 }
   
		 output += "\n \nTop Tweets \n \n"
   
		 #Top Tweets output.
		 top_tweets["top_tweets"].each { |top_tweets_by_type|
   
			if @endpoint != 'totals' or (@endpoint == 'totals' and TOTALS_ENGAGEMENT_TYPES.include?(top_tweets_by_type['type']))
   
			   output += "Top Tweets for #{top_tweets_by_type['type']}: \t #{top_tweets_by_type['type'].capitalize} \t Tweet links:\n"
   
			   top_tweets_by_type["tweets"].each { |top_tweet|
				  output += "#{top_tweet["id"]}#{extra_spaces} \t #{top_tweet["count"].to_s} #{extra_spaces}\t https://twitter.com/lookup/status/#{top_tweet["id"]}\n" unless top_tweet["count"] == 0
			   }
			   output += "\n"
			end
		 }

	  end
	  
	  output += "\n \nNumber of requests: #{@num_requests} \nProcess took #{format('%.01f', process_duration/60)} minutes."

   end
   
   def write_results_file(results)

	  results_file = "#{@outbox}/#{@name}_results.csv"
	  File.open(results_file,'w') {|file| file.write(results.gsub("\t", ','))}

   end

   def generate_tweets_of_interest_for_requests(endpoint = nil)
	  #@tweet_ids holds a 'tweet_ids' array of all 'inbox' tweets. Here we split them into MAX_TWEETS_PER_REQUEST "tweets of interest" parcels.
	  # ====> loads @tweets_of_interest[]
	  #@tweets_of_interest[0] = ['tweet_id_1', .., 'tweet_id_25']
	  #@tweets_of_interest[1] = ['tweet_id_26', .., 'tweet_id_50']

	  endpoint = @endpoint if endpoint.nil?

	  request_tweets = [] #Array of up to MAX_TWEETS_PER_REQUEST.

	  if endpoint == 'historical'
		 tweets_per_request_limit = MAX_TWEETS_PER_REQUEST_HISTORICAL
	  elsif endpoint == '28hr'
		 tweets_per_request_limit = MAX_TWEETS_PER_REQUEST_28HR
	  elsif endpoint == 'totals'
		 tweets_per_request_limit = MAX_TWEETS_PER_REQUEST_TOTALS
	  else
		 AppLogger.log_warn "Specified endpoint not yet supported!"
		 return nil
	  end

	  @tweet_ids.each do |tweet_id|

		 request_tweets << tweet_id

		 if request_tweets.length == tweets_per_request_limit then

			@tweets_of_interest << request_tweets

			request_tweets = []
		 end
	  end

	  #Handle last batch, not already grabbed in USER_LIMIT chunks above.
	  if request_tweets.length > 0 then

		 @tweets_of_interest << request_tweets
	  end

	  @tweets_of_interest

   end

   #If one date specified, anchor the other to it w.r.t. max days.
   #If neither, API will default to start date = now-28 days and end_date to now..
   def set_dates(start_date = nil, end_date = nil)

	  if (start_date.nil? and not end_date.nil?)

		 start_date = (@utils.get_date_object(end_date)) - (MAX_HISTORICAL_DAYS * (24 * 60 * 60))

		 @start_date = start_date.to_s
		 @end_date = end_date.to_s

	  elsif (not start_date.nil? and end_date.nil?)

		 end_date =(@utils.get_date_object(start_date)) + (MAX_HISTORICAL_DAYS * (24 * 60 * 60))

		 if end_date > Time.new.utc
			end_date = nil #Let API default to Now.
		 end

		 @start_date = start_date.to_s
		 @end_date = end_date.to_s if not end_date.nil?

	  end
   end

   #This method: 
   # + knows to exclude time-series Engagement Groupings from /totals requests.
   # + knows that the /totals endpoint supports a subset of Engagement Types.
   # +  
   
   def assemble_request(tweets_of_interest)

	  request = {}

	  request['tweet_ids'] = tweets_of_interest

	  if @endpoint == 'historical'
		 request['start'] = @utils.get_ISO_date_string(@utils.get_date_object(@start_date)) unless @start_date.nil?
		 request['end'] = @utils.get_ISO_date_string(@utils.get_date_object(@end_date)) unless @end_date.nil? #Let API default to now.
	  end

	  request['engagement_types'] = []

	  if @endpoint == 'totals'
		 @engagement_types.each do |engagement_type|
			if TOTALS_ENGAGEMENT_TYPES.include?(engagement_type[0])
			   if engagement_type[1] then
				  request['engagement_types'] << engagement_type[0]
			   end
			end
		 end
	  else
		 @engagement_types.each do |engagement_type|
			if engagement_type[1] then
			   request['engagement_types'] << engagement_type[0]
			end
		 end
	  end

	  #Assemble groupings section.
  	  request['groupings'] = {}
	  @groupings.each do |key, items|
		 
		 
		 if @endpoint == 'totals'

		    if !items.include? 'engagement.hour' and !items.include? 'engagement.day'
			   request['groupings'][key] = {}
			   request['groupings'][key]['group_by'] = []
			   items.each do |item|
			   		request['groupings'][key]['group_by'] << item
   			   end
			else
			   AppLogger.log_info "Not adding time-series grouping to /totals request"
			   @groupings = @groupings.tap { |h| h.delete(key)}
		    end
		 else
			request['groupings'][key] = {}
			request['groupings'][key]['group_by'] = []
			items.each do |item|
			   request['groupings'][key]['group_by'] << item
			end
	     end
	  end

	  request.to_json

   end

   def remove_unowned_tweets_from_request(request, error_msg)


	  request = JSON.parse(request)

	  tweet_ids = []
	  tweet_ids = request['tweet_ids']
	  tweet_ids_to_remove = []
	  error_msg.split(':')[-1].split(',').each { |tweet_id|
		 tweet_ids_to_remove << tweet_id
	  }

	  tweet_ids_to_remove.each { |tweet_id|
		 AppLogger.log_error "Removing Tweet from request: #{tweet_id}"
		 tweet_ids.delete(tweet_id.to_i)
	  }

	  request['tweet_ids'] = tweet_ids

	  request.to_json

   end

   def check_results(results)
	  #Manages errors, including sleeps after rate limit errors.

	  #Some example API errors:
	  #{"errors"=>["Forbidden to access metrics: retweets"]}
	  #{"errors"=>["internal server error"]}
	  #{"errors"=>["Forbidden to access tweets for author id 1114564404: 640022366307745792", "Forbidden to access tweets for author id 18435372: 640026211712786432, 640026277605339136, 640027450420756481", "Forbidden to access tweets for author id 185728888: 640020476375474176, 640020688380821504, 640020920619409408, 640021584342851584, 640021586603569152, 640023513538121728, 640024358136741888, 640024360812707840, 640025909056143360, 640026591184179201, 640026594011148288, 640027929368469504, 640027931822157824, 640028121148821504, 640028123136966656", "Forbidden to access tweets for author id 2265341844: 640022312914407425", "Forbidden to access tweets for author id 22788127: 640023742215663616", "Forbidden to access tweets for author id 244260553: 640027565067931648", "Forbidden to access tweets for author id 2449312615: 640021983225184256", "Forbidden to access tweets for author id 398862690: 640025343227785216", "Forbidden to access tweets for author id 74641010: 640021572414124032"]}.

	  #"Forbidden to access tweets for author id 185728888: 640028123136966656"

	  results['continue'] = true

	  if results['response']['errors'].nil?

		 if !results['response']['unavailable_tweet_ids'].nil?
			AppLogger.log_info("Unavailable Tweet IDs: #{results['response']['unavailable_tweet_ids']}")
		 end

		 return results

	  else #We have an error message from API.

		 results['continue'] = false

		 AppLogger.log_error("Server responded with an Error: #{results}.")

		 results['response']['errors'].each { |error_msg|
			if error_msg.downcase.include?('rate limit')
			   AppLogger.log_error "ERROR, hit rate limit: #{results['response']['errors'][0]}"
			   AppLogger.log_info "Sleeping #{@rate_limit_seconds/@rate_limit_requests} seconds before next API request..."
			   AppLogger.log_info "Client making API request: #{results['request'][0..80]}"
			   results['retry'] = 'rate-limit'
			   results['continue'] = true
			elsif error_msg.downcase.include?("forbidden to access tweets for author id")
			   results['request'] = remove_unowned_tweets_from_request(results['request'], error_msg)
			   results['retry'] = 'forbidden-tweets'
			   results['continue'] = true
			elsif error_msg.downcase.include? ("Your account could not be authenticated") #Bad Consumer Key secret or Access Token secret.
			   AppLogger.log_error "ERROR: Can't authenticate: Please confirm your OAuth keys and tokens."
			elsif error_msg.downcase.include? ("your application id is not authorized.") #Authentication failed.
			   AppLogger.log_error "ERROR: Can't authenticate: Bad Consumer Key secret or Access Token secret?"
			else
			   AppLogger.log_error "ERROR occurred: #{error_msg}."
			end


		 }

		 return results
	  end
   end

   def save_api_response(results)

	  num = 0

	  results_saved = false

	  filename_base = "#{@name}_metrics"
	  filename = filename_base

	  until results_saved
		 if not File.file?("#{@outbox}/metrics/#{filename}.json")
			File.open("#{@outbox}/metrics/#{filename}.json", 'w') { |file| file.write(results.to_json) }
			results_saved = true
		 else
			num += 1
			filename = filename_base + "_" + num.to_s
		 end
	  end

   end

   #=====================================================================================================================
   # Called once when client app is started.
   # Returns true if process finished as expected.
   # Returns false if not.

   def manage_process(endpoint = nil)

	  endpoint = @endpoint if endpoint.nil?

	  @uri_path = "/insights/engagement/#{@endpoint}"

	  if @endpoint == 'historical'

		 @start_date = @utils.set_ISO_date_string(@start_date) if @start_date != nil
		 @end_date = @utils.set_ISO_date_string(@end_date) if @end_date != nil

		 if not (@start_date == nil and @end_date == nil) #Only set dates if one or both are specified. If both are nil, API handles defaults.

			@start_date = @utils.crop_date(@start_date, 'hour', 'before') if @start_date != nil
			@end_date = @utils.crop_date(@end_date, 'hour', 'after') if @end_date != nil

			set_dates(@start_date, @end_date)

		 end
	  end

	  continue = true

	  load_ids if @tweet_ids.length == 0

	  AppLogger.log_info "Generating sets of Tweet IDs for API requests to #{endpoint} endpoint..."

	  @tweets_of_interest = generate_tweets_of_interest_for_requests(endpoint)

	  AppLogger.log_info "Will make #{@tweets_of_interest.count} API requests..."

	  results = {}
	  results['continue'] = true

	  rate_limit_pause = @rate_limit_seconds/@rate_limit_requests
		
	  start_process = Time.now
	  
	  @tweets_of_interest.each do |toi| #These tweets_of_interest items each map to a single request.

		 begin

			results['request'] = assemble_request(toi)
			start_request = Time.now
			@num_requests += 1
			AppLogger.log_info "Making #{@num_requests} of #{@tweets_of_interest.count} requests..."
			results['response'] = JSON.parse(make_post_request(@uri_path, results['request']))
			duration = Time.now - start_request
			results['retry'] = nil

			#--------------------------------------

			results = check_results(results)

			#----------------------------------------

			if results['continue'] # if success, sleep and continue.

			   if results['retry'].nil?
				  AppLogger.log_info "Managing Top Tweets, handling metadata in API response."

				  if @save_api_responses
					 save_api_response(results['response'])
				  end

				  manage_top_tweets(results['response']) unless (@max_top_tweets == 0 or !results['errors'].nil?)

				  if @tweets_of_interest.count > 1
			    	 AppLogger.log_info "Sleeping #{format('%.02f', rate_limit_pause - duration)} seconds before next API request... " if duration < rate_limit_pause
					 sleep (rate_limit_pause - duration) if duration < rate_limit_pause
				  end
			   else #some error that has a try-again reaction...
				  #Like hitting a rate limit
				  if results['retry'] == 'rate-limit'
					 AppLogger.log_warn "Rate-limit hit, sleeping #{rate_limit_pause} seconds before next API request..."
					 sleep (rate_limit_pause)
					 results['response'] = JSON.parse(make_post_request(@uri_path, results['request']))
				  elsif results['retry'] == 'forbidden-tweets'
					 AppLogger.log_warn "Retrying after forbidden Tweets removed from request... Sleeping #{rate_limit_pause} seconds before next API request..."
					 sleep (rate_limit_pause)
					 results['response'] = JSON.parse(make_post_request(@uri_path, results['request']))
				  else
					 AppLogger.log_warn "Error not handled?"

				  end
			   end
			else
			   AppLogger.log_info "An 'no retry' type error occurred. Quitting... "
			   continue = false
			   return continue

			end
			
		 rescue
			AppLogger.log_error "ERROR occurred, skipping request."
		 end
	  end
	  
	  @process_duration = Time.now - start_process

	  AppLogger.log_info "Sorting Top Tweets..."
	  sort_top_tweets(@top_tweets) unless (@max_top_tweets == 0 or @top_tweets.nil?)
	  continue

   end

   def files_to_ingest?
	  files_to_ingest = false
	  #Do we have files to process?
	  AppLogger.log_info "Checking inbox for files to process..."
	  files = Dir.glob("#{@inbox}/*.{json, gz}")
	  files += Dir.glob("#{@inbox}/*.{csv}")
	  files_to_ingest = true if files.length > 0
	  files_to_ingest
   end

   def load_ids

	  metadata = {}
	  id_type = 'tweet_ids'

	  files = Dir.glob("#{@inbox}/*.{json, gz}")
	  if files.length > 0
		 AppLogger.log_info "Found JSON or GZ files to process... Parsing out #{id_type}..."
		 id_types = []
		 id_types << id_type
		 metadata = @utils.load_metadata_from_json(@inbox, id_types, @verbose)
		 metadata["#{id_type}"]
	  end

	  files = Dir.glob("#{@inbox}/*.{csv}")
	  if files.length > 0
		 AppLogger.log_info "Found CSVs... Parsing out #{id_type}..."
		 metadata = @utils.load_metadata_from_csv(@inbox, id_type, @verbose)
	  end

	  #if @save_ids then
	  #	 puts 'Saving Parsed IDs has not been implemented.'
	  #end

	  metadata[id_type]
   end

end

