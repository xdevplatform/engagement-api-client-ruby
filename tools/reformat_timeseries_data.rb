=begin

Script that takes the Engagement API's native time-series JSON output and reformats the data with 'standard' timestamps.
Generates simple CSV files, making it easier to work with tools such as R and spreadsheets.

This code depends on the following Engagement Groupings:

 timeseries_hourly:
    - tweet.id
    - engagement.type
    - engagement.day
    - engagement.hour
  timeseries_daily:
    - tweet.id
    - engagement.type
    - engagement.day
  hour_of_day:
    - tweet.id
    - engagement.type
    - engagement.hour

Given the following Engagement Types configuration:

engagement_types:
  impressions: true
  engagements: true
  retweets: true
  favorites: true
  replies: true
  url_clicks: true

Produces output formated as:

timestamp, impressions, engagements, retweets, favorites, replies, url_clicks

=end

require_relative '../common/app_logger'
require_relative '../lib/engagement_client'

require 'optparse'
require 'fileutils'
require 'csv'

if __FILE__ == $0 #This script code is executed when running this file.

   #-----------------------------------------------------
   metadata = "./outbox/mymetrics/metrics/history-top-tweet_metrics.json" #This is the Engagement API server response with time-series data you want to reformat.
   outbox = "../outbox/time-series"
   #-----------------------------------------------------
   
   file = File.read(metadata)
   metrics_hash = JSON.parse(file)

   timeseries_hourly = metrics_hash['timeseries_hourly']

   #-----------------------------------------------------
   #Build header - same header for all time-series data.
   header_items = []
   header_items << 'date'

   key, metrics = timeseries_hourly.first

   metrics.each do |metrics|
	  header_items << metrics[0]
   end
   
   header = header_items.join(',')

   #-----------------------------------------------------
   #Build CSV with hourly time-series data.
   time_series = {}

   timeseries_hourly.each do |tweet|
	  puts tweet[0]

	  tweet[1].each do |metric_type|
		 puts metric_type[0]
		 metric_type[1].each do |day_key|
			day_key[1].each do |hour_key|

			   date_key = "#{day_key[0]} #{hour_key[0]}:00"
			   #puts date_key

			   #If key exists, retrieve value, and append hour_key[1]
			   if time_series.key?(date_key)
				  data = time_series[date_key]
				  time_series[date_key] = "#{data},#{hour_key[1]}"
			   else
				  time_series[date_key] = hour_key[1]
			   end
			end
		 end
	  end

	  #Write Tweet CSV
	  csv_filename = File.expand_path("../#{tweet[0]}_hourly_timeseries",__FILE__)
	  csv_file = File.open(csv_filename, "w")

	  csv_file.puts header

	  time_series.each do |time_step|
		 time_stamp = "#{time_step[0]}"
		 csv_file.puts "#{time_stamp}, #{time_step[1]}"
	  end

	  csv_file.close #Close new CSV file.

   end

   #-----------------------------------------------------
   #Build CSV with daily time-series data.
   timeseries_daily = metrics_hash['timeseries_daily']

   time_series = {}

   timeseries_daily.each do |tweet|
	  puts tweet[0]

	  tweet[1].each do |metric_type|
		 puts metric_type[0]
		 metric_type[1].each do |day_key|
			date_key = "#{day_key[0]}"
			#puts date_key

			#If key exists, retrieve value, and append hour_key[1]
			if time_series.key?(date_key)
			   data = time_series[date_key]
			   time_series[date_key] = "#{data},#{day_key[1]}"
			else
			   time_series[date_key] = day_key[1]
			end
		 end
	  end

	  #Write Tweet CSV
	  csv_filename = File.expand_path("../#{tweet[0]}_daily_timeseries",__FILE__)
	  csv_file = File.open(csv_filename, "w")

	  csv_file.puts header

	  time_series.each do |time_step|
		 time_stamp = "#{time_step[0]}"
		 csv_file.puts "#{time_stamp}, #{time_step[1]}"
	  end

	  csv_file.close #Close new CSV file.

   end

   #-----------------------------------------------------
   #Build CSV with hour-of-day time-series data.
   hour_of_day = metrics_hash['hour_of_day']
   time_series = {}

   hour_of_day.each do |tweet|
	  puts tweet[0]

	  tweet[1].each do |metric_type|
		 puts metric_type[0]
		 metric_type[1].each do |hour_of_day|

			#If key exists, retrieve value, and append hour_key[1]
			if time_series.key?(hour_of_day[0])
			   data = time_series[hour_of_day[0]]
			   time_series[hour_of_day[0]] = "#{data},#{hour_of_day[1]}"
			else
			   time_series[hour_of_day[0]] = hour_of_day[1]
			end
		 end
	  end

	  #Write Tweet CSV
	  csv_filename = File.expand_path("../#{tweet[0]}_hour_of_day.csv",__FILE__)
	  csv_file = File.open(csv_filename, "w")

	  csv_file.puts header

	  time_series.each do |time_step|
		 time_stamp = "#{time_step[0]}:00"
		 csv_file.puts "#{time_stamp}, #{time_step[1]}"
	  end

	  csv_file.close #Close new CSV file.

   end
end
   
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
