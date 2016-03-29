require 'time'

require_relative '../common/app_logger'
include AppLogger

class InsightsUtils

   attr_accessor :verbose

   def initialize(verbose = nil)
	  if verbose.nil?
		 @verbose = true
	  else
		 @verbose = verbose
	  end
   end

   def load_metadata_from_csv(inbox, type, verbose = nil)
	  #Returns a 'metadata' hash with 'tweet_ids'and 'user_ids' keys with array values.

	  #types = 'tweet_ids' or 'user_ids'. #Simple string since this method parses only one type.
	  #Pass in a hash of metadata 'keys' and have them returned.
	  #Parses the inbox of Tweets and returns what you ask for.

	  #Navigate CSV files. These files have either User IDs or Tweet IDs.
	  #Audience API client is looking for User IDs.
	  #Engagement API is looking for Tweet IDs.

	  metadata = {}
	  ids = []

	  files = Dir.glob("#{inbox}/*.csv")

	  AppLogger.log_info("Have #{files.length} files to process...")

	  files.each { |file|

		 header = File.readlines(file)[0]

		 if type == 'user_ids' and !header.include? 'user_id'
			return metadata #Nothing to do here.... 
		 end

		 if type == 'tweet_ids' and !header.include? 'tweet_id'
			return metadata #Nothing to do here.... 
		 end

		 File.readlines(file).drop(1).each do |line|
			ids << line.strip.to_i if not line.strip! == ''
		 end

		 #Move file to 'processed' folder
		 FileUtils.mv(file, "#{inbox}/processed/#{file.split('/')[-1]}")

	  }

	  AppLogger.log_info("Loaded #{ids.length} #{type} IDs...")

	  if type == 'user_ids'
		 metadata['user_ids'] = ids.uniq
	  else
		 metadata['tweet_ids'] = ids.uniq
	  end

	  metadata

   end

   def load_metadata_from_json(inbox, types, verbose = nil)
	  #types = ['tweet_ids', 'user_ids'] #Is an array since this method can parse out multiple types.
	  #Pass in a hash of metadata 'keys' and have those types returned.
	  #Parses the inbox of Tweets and returns what you ask for.

	  #Using Engagement API, tweet_ids = oCommon.load_metadata('tweet_ids')
	  #Using Audience API, user_ids = oCommon.load_metadata('user_ids')
	  #Using both? ids = oCommon.load_metadata('tweet_ids',user_ids')

	  #verbose lets calling object decide whether to chat to standard out. Defaults to false. 

	  AppLogger.log_info("Parsing files in inbox. Loading metadata: #{types}")

	  metadata = {}

	  user_ids = []
	  tweet_ids = []

	  count = 0

	  #Navigate Tweets files.
	  files = Dir.glob("#{inbox}/*.{json,gz}")

	  AppLogger.log_info("Have #{files.length} files to process...")

	  files.each { |file|

		 puts "Processing #{file}... " if verbose

		 if file.split('.')[-1] == 'gz' #gzipped?

			new_name = file.split('.')[0..-2].join('.')

			Zlib::GzipReader.open(file) { |gz|
			   g = File.new(new_name, "w")
			   g.write(gz.read)
			   g.close
			}

			File.delete(file)

			file = new_name

		 end

		 contents = File.read(file)

		 activities = []

		 #Handling various Gnip outputs, so some self-discovery.
		 if (contents.start_with?('{"results":[') or contents.start_with?('{"next":'))

			json_contents = JSON.parse(contents)

			json_contents["results"].each do |activity|
			   activities << activity.to_json if activity['id'] != nil
			end

		 elsif contents.include?('"info":{"message":"Replay Request Completed"')
			contents.split("\n")[0..-2].each { |line| #drop last "info" member.
			   if line.include?('"id":"')
				  activities << line
			   end
			}
		 elsif contents.start_with?('{"ids":[')
			json_contents = JSON.parse(contents)

			user_ids += json_contents['ids']
		 elsif contents.start_with?('{"statuses":[') #Public GET search/tweets 
			json_contents = JSON.parse(contents)

			json_contents["statuses"].each do |activity|
			   activities << activity.to_json
			end
		 else
			#No root-level key, assuming a 'headless' JSON array, such as returned from Public get statuses like calls.
			#E.g., Public GET statuses/lookup and GET statuses/user_timeline.
			json_contents = JSON.parse(contents)

			json_contents.each do |activity|
			   activities << activity.to_json if activity['id'] != nil
			end
		 end
		 
		 if activities.count == 0
			AppLogger.log_info "No Tweets found in file #{file}..."
		 end

		 activities.each { |activity|

			count += 1

			begin
			   activity_hash = JSON.parse(activity)
			rescue Exception => e
			   AppLogger.log_error("ERROR in convert_files: could not parse activity's JSON: #{e.message}")
			end

			types.each do |type|

			   if type == 'user_ids'

				  #Handle both 'original' and AS Tweet formats.
				  if !activity_hash['actor'].nil?
					 user_id = activity_hash['actor']['id'].split(":")[-1] #parse out tweet_id
				  else
					 user_id = activity_hash['user']['id']
				  end

				  user_ids << user_id #add to list

			   end

			   if type == 'tweet_ids'
				  #Handle both 'original' and AS Tweet formats.
				  if activity_hash['id'].is_a? String and activity_hash['id'].include?('twitter.com')
					 tweet_id = activity_hash['id'].split(":")[-1] #parse out tweet_id
				  else
					 tweet_id = activity_hash['id']
				  end

				  tweet_ids << tweet_id #add to list
			   end
			end
		 }

		 #Move file to 'processed' folder
		 FileUtils.mv(file, "#{inbox}/processed/#{file.split('/')[-1]}")

	  } #open file loop

	  #OK, package these metadata up...
	  if tweet_ids.count > 0
		 AppLogger.log_info("Parsed #{tweet_ids.count} Tweets...")
		 metadata['tweet_ids'] = tweet_ids
	  end

	  #if parsing user ids
	  if user_ids.count > 0
		 AppLogger.log_info("Parsed #{user_ids.count} User IDs...")
		 user_ids = user_ids.uniq
		 AppLogger.log_info("De-duplicating User ID list. Have #{user_ids.count} unique User IDs...")
		 metadata['user_ids'] = user_ids
	  end

	  metadata

   end

   def get_api_access(keys, base_url)

	  consumer = OAuth::Consumer.new(keys['consumer_key'], keys['consumer_secret'], {:site => base_url})
	  token = {:oauth_token => keys['access_token'],
			   :oauth_token_secret => keys['access_secret']
	  }

	  return OAuth::AccessToken.from_hash(consumer, token)

   end

   def restore_files
	  #Restores inbox by moving processed files from /processed folder.

	  #Navigate Tweets files.
	  files = Dir.glob("#{inbox}/processed/*.{json}")

	  AppLogger.log_info("Have #{files.length} files to restore...")

	  files.each { |file|

		 #Move file to 'processed' folder
		 FileUtils.mv(file, "#{inbox}#{file.split('/')[-1]}")
	  }

   end


   #Timestamps come in as a string, leave as a string.
   def crop_date(date, interval, direction)

	  date = get_date_object(date)

	  if direction == 'before'
		 if interval == 'minute'
			if date.second > 0
			   date = date - 60
			   date = Time.utc(date.year, date.month, date.day, date.hour, date.min, 0)
			end
		 elsif interval == 'hour'
			if date.min > 0
			   date = date - (60 * 60)
			   date = Time.utc(date.year, date.month, date.day, date.hour, 0, 0)
			end
		 elsif interval == 'day'
			date = Time.utc(date.year, date.month, date.day, 0, 0, 0)
		 end
	  elsif direction == 'after'
		 if interval == 'minute'
			if date.second > 0
			   date = date + 60
			   date = Time.utc(date.year, date.month, date.day, date.hour, date.min, 0)
			end
		 elsif interval == 'hour'
			if date.min > 0
			   date = date + (60 * 60)
			   date = Time.utc(date.year, date.month, date.day, date.hour, 0, 0)
			end
		 elsif interval == 'day'
			date = date + (60 * 60 * 24)
			date = Time.utc(date.year, date.month, date.day, 0, 0, 0)
		 end

	  end

	  return date.to_s

   end

   def numeric?(object)
	  true if Float(object) rescue false
   end

   def get_date(input = nil)

	  date = Time.new.utc
	  now = Time.new.utc

	  if input.nil?
		 return now
	  end

	  input = input.to_s

	  #Handle minute notation.
	  if input.downcase[-1] == "m"
		 date = now - (60 * input[0..-2].to_f)
		 return date
	  end

	  #Handle hour notation.
	  if input.downcase[-1] == "h"
		 date = now - (60 * 60 * input[0..-2].to_f)
		 return date
	  end

	  #Handle day notation.
	  if input.downcase[-1] == "d"
		 date = now - (24 * 60 * 60 * input[0..-2].to_f)
		 return date
	  end

	  #Handle PowerTrack format, YYYYMMDDHHMM
	  if input.length == 12 and numeric?(input)
		 date = get_date_object(input)
		 return date
	  end

	  #Handle "YYYY-MM-DD 00:00"
	  if input.length == 16
		 date = get_date_object(input)
		 return date
	  end

	  #Handle ISO 8601 timestamps, as in Twitter payload "2013-11-15T17:16:42.000Z"
	  if input.length > 16
		 date = Time.parse(input)
		 return date
	  end

	  return 'Error, unrecognized timestamp.'

   end

   #Takes a variety of string inputs and returns a standard Gnip YYYYMMDDHHMM timestamp string.
   def set_Gnip_date_string(input = nil)
	  date = get_date(input)
	  return get_Gnip_date_string(date) if date.is_a? Time
   end

   #Takes a variety of string inputs and returns an ISO YYYY-MM-DDTHH:MM:SS.000Z timestamp string.
   def set_ISO_date_string(input = nil)
	  date = get_date(input)
	  return get_ISO_date_string(date) if date.is_a? Time
   end

   def get_Gnip_date_string(time) #--> "YYYYMMDDHHMM"
	  return time.year.to_s + sprintf('%02i', time.month) + sprintf('%02i', time.day) + sprintf('%02i', time.hour) + sprintf('%02i', time.min)
   end

   def get_ISO_date_string(time) #-->"YYYY-MM-DDTHH:MM:00Z"
	  return "#{time.year.to_s}-#{sprintf('%02i', time.month)}-#{sprintf('%02i', time.day)}T#{sprintf('%02i', time.hour)}:#{sprintf('%02i', time.min)}:00Z"
   end

   def get_date_object(time_string)

	  time = Time.new
	  if time_string.nil?
		 time = Time.now.utc
	  else
		 time = Time.parse(time_string)
	  end


	  return time
   end


end

