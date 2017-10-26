# engagement-api-client-ruby
## An example Engagement API client written in Ruby.

+ [Introduction](#introduction)
  + [Overview](#overview)
  + [User-story](#user-story)
  + [API Endpoints](#api-endpoints)
  + [Example Session](#example-session)
+ [Getting Started](#getting-started)
  + [Configuring Client](#configuring-client) 
    + [Account Configuration](#account-configuration) 
    + [App Setting Configuration](#app-settings-configuration) 
    + [Engagement Types](#engagement-types) 
    + [Engagement Groupings](#engagement-groupings) 
    + [Logging](#logging) 
    + [Command-line Options](#command-line-options)
+ [Details](#details)
    + [Ingesting Tweet IDs](#ingesting-tweet-ids)
    	+ [Handling Unowned Tweets](#unowned-tweets) 
    + [Client Output](#output)
    	+ [API Responses](#api-responses) 
    	+ [Top Tweets](#top-tweets) 
    + [Specifying Start and End Times for Historical Request](#specifying-times)
+ [Code Details](#code-details) 
    + [engagement_app.rb](#engagement-app).
    + [engagement_client.rb](#engagement-client).
    + [insights_utils.rb](#insights-utils).
    + [app_logger.rb](#app-logger).

## Introduction <a id="introduction" class="tall">&nbsp;</a>

### Overview <a id="overview" class="tall">&nbsp;</a>

The Engagement API provides access to organic engagement metrics, enabling publishers, advertisers, and brands to retrieve metrics around their organic engagement and reach. These metrics can be used to assess engagements and impressions around Tweets and Retweets. See http://support.gnip.com/apis/engagement_api/ for API documentation.

The Engagement API is a member of the [Gnip Insights APIs](https://blog.twitter.com/2015/gnip-insights-apis). See [HERE](https://github.com/twitterdev/audience-api-client-ruby) (soon!) if you are interested in a related example client for the [Audience API] (http://support.gnip.com/apis/audience_api/). 

This example Engagement API Client helps manage the process of generating engagement metadata for large (or small!) Tweet collections. The Client ingests Tweet ID collections, generates and manages a series of API requests, and helps organize the engagement metrics into grand totals while surfacing 'top' Tweets.  

The Engagement API requires 3-legged OAuth authentication. Signing a request requires both an access token for your Twitter application (client application) and a token for the user you are requesting data on behalf of. A first step is getting access to the Engagement API and creating a Twitter App used to authenticate. You can generate user tokens using the Sign in with Twitter process. See the [Getting Started](#getting-started) section below for more information. 

This Client provides the following 'helper' methods and features:

+ Extracting Tweet IDs from a variety of sources. These sources include Gnip [Full-Archive Search](http://support.gnip.com/apis/search_full_archive_api/), [30-Day Search](http://support.gnip.com/apis/search_api/), or [Historical PowerTrack](http://support.gnip.com/apis/historical_api/) products, [several Twitter Public API endpoints](#twitter-public-endpoints), and simple CSV files. 
+ Surfacing ['Top Tweets.'](#top-tweets) As engagement metrics are retrieved, on a Tweet-by-Tweet basis, this client maintains a list of 'Top Tweets' with the highest levels of engagement. For example, if you are processing 100,000 Tweets, it can compile the top 10 for Retweets or any other available metric.
+ Support for managing Engagement metric data sets. A name can be specified for each run and the resulting summary and metric response JSON files are assigned that name and placed in a folder with the name. This helps keep your various data sets organized.   
+ Handling unowned Tweets. If you make a request containing an unowned Tweet ID, the API will reject the entire request, even if all the other IDs are owned. If this occurs the Client will remove any unowned IDs and resubmit the request.
+ Ability to tune request intervals to prevent rate limits. 

### User-story <a id="user-story" class="tall">&nbsp;</a>

As a Gnip customer who is adopting the Engagement API: 

+ I want to automate the generation of requests needed to exercise the API.
	+ Assembles the (JSON) API request payloads.
		+ The ```/28hr``` and ```/historical``` endpoints support up to 25 Tweet IDs per request, while the ```/totals``` supports 250.
		+ Some Tweet collections may require hundreds or thousands of API requests.

+ I have collections of Tweet IDs and want to easily retrieve engagement metrics for them. These collections consist of:
    + Tweets collected with a Gnip Product such as [Full-Archive Search](http://support.gnip.com/apis/search_full_archive_api/), [30-Day Search](http://support.gnip.com/apis/search_api/), or [Historical PowerTrack](http://support.gnip.com/apis/historical_api/).
        + If extracting IDs from Tweets, the Client handles both 'original' and Activity Stream Tweet formats.
    + Tweets returned from the Twitter Public API, such as [GET statuses/lookup](https://dev.twitter.com/rest/reference/get/statuses/lookup).
    + A simple CSV file generated from a datastore.

+ I want it to aggregate metadata from the API responses, while creating some basic output for analysis and links to 'top' Tweets.
   + Formats aggegrate grand totals and 'Top Tweets' into a simple CSV format
   + Includes clickable links to view Top Tweets. 

### API Endpoints <a id="api-endpoints" class="tall">&nbsp;</a>

As described [HERE](http://support.gnip.com/apis/engagement_api/overview.html), there are 3 Engagement API endpoints:

An endpoint can be specified in the client's configuration, or passed in via the -p command-line parameter. 

+ Current Totals (default): Returns the current all-time totals for select metrics. ```$ruby engagement_app.rb -p "totals"``` 
	+ As of February 2016, this endpoint supports a subset of engagement metrics. See [HERE](#digging-into-the-code) for information on where this subset is specified in the code.
+ Last 28 hours: Returns the metrics that have occurred in thhe most recent 28 hours. Can report on aggregate totals or Tweet-by-Tweet daily and hourly time-series.  ```$ruby engagement_app.rb -p "28hr"```
+ Historical: Returns the metrics for any four-week period (28-day) going back to September 1, 2014. Can report on aggregate totals or Tweet-by-Tweet daily and hourly time-sereis. ```$ruby engagement_app.rb -p "historical"```

### Example Session <a id="example-session" class="tall">&nbsp;</a>

For this example we'll take a look at the Retweet, Replies, and Favorites metrics for all of the @Gnip Tweets since September 1, 2014. While collecting this metric data, we want to identify the top 3 tweets in these metric categories. The first step is to have the @Gnip account owner provide access tokens providing access to Engagement metrics for their Tweets. With those tokens the steps are:

+ Configure the account.yaml file with tokens.
+ Compile the Tweets to be analyzed. For this exercise, this [Full-Archive Search (FAS) client](https://github.com/gnip/gnip-fas-ruby) was used. JSON responses from the FAS API were written to the Client's inbox, consisting of 138 Tweets. 
+ Configure the Client:
    + Name the dataset 'Gnip': -n Gnip
    + Specify the 'totals' endpoint: -p totals
    + Configure the Engagement Types and Groupings. These are configured in the app_settings.yaml file. See [HERE](http://support.gnip.com/apis/engagement_api/overview.html#EngagementTypes) for a list of available Types and [HERE](http://support.gnip.com/apis/engagement_api/overview.html#EngagementGroupings) for how the metrics can be grouped.
    + Specify the number of top Tweets to surface: ```max_top_tweets: 3```
+ Run the Client app: $ruby engagement_app.rb -n Gnip -p totals
+ Look in the outbox for the Engagement API results
    
Two types of files are generated: ```Gnip_results.csv``` and ```Gnip_metrics.json```. These are written to a ```Gnip``` subfolder (automatically created and named based on the dataset name) of your configured inbox. Since some data sets may produce a large number of API metric responses, the ```_metrics.json``` files are written to a ```metrics``` subfolder, and the file names are numerically serialized.
 
Here are the contents of the Gnip_results.csv file:

```
Engagement API Results

Number of Tweets: 138

Engagement Type                 Total
Favorites            1262
Retweets            952
Replies            57

Top Tweets

Top Tweets for favorites:      favorites      Tweet links:
629325318294114305            282        https://twitter.com/lookup/status/629325318294114305
631148159138316288            126        https://twitter.com/lookup/status/631148159138316288
621734831659970562            48        https://twitter.com/lookup/status/621734831659970562

Top Tweets for retweets:      retweets      Tweet links:
629325318294114305            124        https://twitter.com/lookup/status/629325318294114305
631148159138316288            102        https://twitter.com/lookup/status/631148159138316288
644194031107506176            48        https://twitter.com/lookup/status/644194031107506176

Top Tweets for replies:      replies      Tweet links:
629325318294114305            19        https://twitter.com/lookup/status/629325318294114305
631148159138316288            4        https://twitter.com/lookup/status/631148159138316288
507665063772454912            4        https://twitter.com/lookup/status/507665063772454912

```

This Tweet collection required a single call to the ```/totals``` endpoint, so in about one second we see that the following Tweet was the most engaged Tweet since September 2014. 

 ![](https://github.com/twitterdev/engagement-api-client-ruby/blob/master/images/Gnip_top_tweet.png)

## Getting started <a id="getting-started" class="tall">&nbsp;</a>

+ Obtain access to the Engagement API from Twitter via Gnip.
+ Create a Twitter App at https://apps.twitter.com, and generate OAuth Keys and Access Tokens.
	+ Obtain Access Tokens for partner accounts that you do not 'own.' These are the Access Tokens for your customer and can be obtained through the Sign In With Twitter process.
+ Compile a collection of Tweet IDs.
+ Deploy client code
    + Clone this repository.
    + Using the Gemfile, run bundle
+ Configure both the Accounts and App configuration files.
    + Config ```accounts.yaml``` file with OAuth keys and tokens.
    + Config ```app_settings.yaml``` file with processing options, Engagement Types, and Engagement Groupings.
    + See the [Configuring Client](#configuring-client) section for the details.
+ Execute the Client using [command-line options](#command-line-options).
    + To confirm everything is ready to go, you can run the following command:

    ```
    $ruby engagement_app.rb 
    ```
    If running with no Tweet IDs to process, the following output is at least a sign that the code is ready to go:
    
    ```
Checking inbox for files to process...
No Tweet IDs to process, quitting.
    ```

### Configuring Client <a id="configuring-client" class="tall">&nbsp;</a>

There are two [YAML](http://www.yaml.org/spec/1.2/spec.html#id2708649) files used to configure the Engagement API client:

+ Account settings: holds your OAuth consumer keys and access tokens. The Engagement API requires 3-legged authorization 
for all endpoints. Additionally, Twitter must approve your client application before you can access the API.
    + Defaults to ./config/account.yaml
    + Alternate file name and location can be specified on the command-line with the -a (account) parameter.
    
+ Application settings: used to specify several application options, as well as the Engagement Types and Groupings.
    + Defaults to ./config/app_settings.yaml.
    + Alternate file name and location can be specified on the command-line with the -c (config) parameter.
    
So, if you are using different file names and paths, you can specify them with the -a and -c command-line parameters:

```
  $ruby engagement_app.rb -l -a "./my_path/my_account.yaml" -c "./my_path/my_settings.yaml"
```

#### Account Configuration - ```accounts.yaml``` <a id="account-configuration" class="tall">&nbsp;</a>

 The Engagement API requires 3-legged authorization for all endpoints. 

+ ```account.yaml```: contains OAuth details, including API consumer keys for a Twitter App that has been provided access to
the Engagement API. The Engagement API requires 3-legged authorization for all endpoints. Twitter must approve your client application before you can access the API.  

Twitter apps can be created at http://dev.twitter.com/apps. When you create an App it will be assigned a numeric App ID. Once an App is created you can generate consumer keys and secrets. To obtain access to the Engagement API, contact your Gnip Account representative or reach out to info@gnip.com to start the process. Access tokens are provided by and on behalf of a Twitter account giving permission to access Tweet Engagement metadata for Tweets it 'owns.' So if you are getting engagement metrics on the behalf of others, you will be managing a set of those access tokens when authenticating with the API. 

```
#OAuth tokens and key for Audience API.
engagement_api:
  
  consumer_key:
  consumer_secret:
  
  #Access token/secret
  access_token:
  access_token_secret:
  
  app_id:  #Not used in code, but useful troubleshooting information.
  
```

#### App Settings Configuration - ```app_settings.yaml``` <a id="app-settings-configuration" class="tall">&nbsp;</a>

This file is used to configure [application options](#application-options), [Engagement Types](#engagement-types), [Engagement Groupings](#engagement-groupings) and [logging](#logging) options.

##### Application options <a id="application-options" class="tall">&nbsp;</a>

Used to specify the Engagement API endpoint, several application options, as well as the Engagement Types and Groupings.

```
#Engagement API ------------------------
engagement_settings:
  name: my_dataset
  endpoint: historical                #options: totals, 28hr, historical.
  start: '2015-11-20'                 #historical endpoint, defaults to now - 28 days.
  end: '2015-12-10'                   #historical endpoint, defaults to now.
  
  inbox: './inbox'                    #Tweet inbox (HPT gz files? Search JSON?, CSV database dump?)
  outbox: './outbox'                  #Engagement API output is written here.
  verbose: true                       #More status fyi written to system out while running.
  
  max_top_tweets: 10                  #Set to zero to turn 'top Tweet' processing off.
 
  save_ids: true                      #TODO: Not implemented yet.
  save_api_responses: true            #Saves Engagement API responses to a 'api_responses' subfolder of the 'outbox'.
  
  rate_limit_requests: 2              #Set these to help avoid request rate limits.
  rate_limit_seconds: 60              #Time between calls equals rate_limit_seconds/rate_limit_requests (60/4 = 15) seconds.

```  

##### Engagement Types <a id="engagement-types" class="tall">&nbsp;</a>

Each Engagement API request requires an "engagement_types" JSON attribute that indicates the types of engagement metrics you want to retrieve: 

```
{
  "engagement_types": [
    "impressions",
    "engagements",
    "retweets",
    "replies",
    "favorites"
  ]
}
```

Metrics of interest are set with a true/false value under the ```engagement_types:``` key in the app settings YAML file. If an engagement type is present and set to 'true' the Client will include that in the JSON ```engagement_type:``` JSON and include it in the API request. If the type is not included, or set to 'false', it is not included in the request JSON.

The order of these engagement types will determine the order of results in the app's output.

```
engagement_types: #order here is echoed in client output.
  impressions: true
  engagements: true
  retweets: true
  replies: true
  favorites: true
  url_clicks: false
  hashtag_clicks: false
  detail_expands: false
  media_clicks: false
  permalink_clicks: false
  app_opens: false
  app_install_attempts: false
  email_tweet: false
```

Note: the ```/totals``` endpoint currently supports Retweets, Replies and Favorites. The Client is currently set to submit only those Types to the ```/totals``` endpoint, regardless of what other Types are set to 'true.' As discussed [HERE](#digging-into-the-code```), the available types are set in a TOTALS_ENGAGEMENT_TYPES array constant in the engagement_client.rb class.


##### Engagement Groupings <a id="engagement-groupings" class="tall">&nbsp;</a>

Each Engagement API request requires a ```groupings:``` JSON attribute with up to ten custom metric groupings. These groupings enable you to receive engagement data organized the way you want. Each Grouping is specified under a custom name, and API returns JSON with those custom names as attributes. For more details on specifying the Engagement Groupings see the [Engagement API documentation](http://support.gnip.com/apis/engagement_api/api_reference.html). [TODO: update link to new subject anchor]

Custom Groupings are specified the ```engagement_groupings:``` key in the app settings YAML file: 

```
engagement_groupings:
  grand_totals:  #Grand totals by Engagement Type.
    - engagement.type
  by_tweet_type: #Needed for surfacing Top Tweets. I.e., the 'top Tweet' code depends on this specific API output.
    - tweet.id
    - engagement.type
```

As noted in the above example, if you are using the 'Top Tweets' feature (by setting ```max_top_tweets:``` to a non-zero value), you must have the ```by_tweet_type:``` Grouping (as configured above) included in your Groupings.

The ```/historical``` and ```/28hr``` endpoints support getting hourly and daily time-series of engagement metrics using the ```engagement.day``` and ```engagement.hour``` values. For example, to generate a hourly time-series of impressions by Tweet ID, that Engagement Type is set to 'true' and the Engagement Groupings are ordered by type, then ID, then by hour:

```
engagement_types: #order here is echoed in output.
  impressions: true

engagement_groupings:
  hourly_timeseries: 
    - engagement.type
    - tweet.id
    - engagement.hour
```

This will produce the following API response, with the root-level ```hourly_timeseries:``` attribute containing output reflecting the Grouping hierarchy :

```
{
  "start": "2016-01-12T20:00:00Z",
  "end": "2016-02-09T19:43:00Z",
  "hourly_timeseries": {
    "impressions": {
      "695310089847111681": {
        "00": "18",
        "01": "6",
        "02": "6",
        "03": "15",
        "04": "16",
        "05": "4",
        "06": "7",
        "07": "14",
        "08": "1",
        "09": "11",
        "10": "2",
        "11": "3",
        "12": "0",
        "13": "8",
        "14": "2",
        "15": "1",
        "16": "8",
        "17": "15",
        "18": "167",
        "19": "57",
        "20": "24",
        "21": "13",
        "22": "6",
        "23": "8"
      }
    }
  }
}
```

**Note** that not all of the Engagement API endpoints support all of the available groupings. For example, the ```/totals``` endpoint does not provide metrics time-series data so specifying the ```engagement.hour``` and ```engagement.day``` Groupings will produce an API error:

```["One or more of the groupBys you have specified are not supported: (engagement.hour). Please adjust your request and try again."]```

##### Logging <a id="logging" class="tall">&nbsp;</a>

This Client uses (mixes-in) a simple AppLogger module based on the 'logging' gem. This singleton 
object is thus shared by the Client app and its helper objects. If you need to implement a different logging design,
that should be pretty straightforward... Just replace the `AppLogger.log` calls with your own logging signature. 

The logging system maintains a rolling set of files with a custom base filename, directory, and maximum size. 

The `app_settings.yaml` file contains the following logging settings:

```
logging:
  name: audience_app.log
  log_path: ./log
  warn_level: debug
  size: 1 #MB
  keep: 2
```  

#### Command-line Options <a id="command-line-options" class="tall">&nbsp;</a>

The Client supports the command-line parameters listed below. Either the single-letter or verbose version of the parameter can be used. 

+    -a, --account -->           Account configuration file (including path) that provides API keys for access.
+    -c, --config -->            Settings configuration file (including path) that provides app settings.
+    -n, --name -->              A name for this dataset. Resulting output files and folder use this.
+    -p, --endpoint -->          Engagement API endpoint to request from: totals, 28hr or historical. 
+    -s, --start -->             Start time when using the historical endpoint.
+    -e, --end -->               End time when using the historical endpoint.
+    -v, --verbose -->           When verbose, output all kinds of things, each request, most responses, etc.
+    -h, --help -->              Display this screen.

Command-line parameters override any equivalent settings found in the app_settings.yaml configuration file. For example:

+ -a overrides the default of ./config/accounts.yaml
+ -c overrides the default of ./config/app_settings.yaml
+ -n overrides name: config file setting.
+ -s overrides start_date: config file setting. 
+ -e overrides end_date: config file setting.
+ -p overrides endpoint: config file setting.
+ -v overrides verbose: config file setting.

##### Command-line examples

Here are some command-line examples to help illustrate how they work:

+ Pass in custom configuration file names/paths and request from the ```/28hr``` endpoint: 

  ```$ ruby engagement_app.rb -a "./my_path/my_account.yaml" -c "./my_path/my_settings.yaml" -p "28hr"```

+ Using default configuration file names and path, request a two-week period from the ```/historical``` endpoint:

 ```$ ruby engagement_app.rb -n my_campaign -p historical -s 201601010000 -e 2016001150000```
  
  
  
## Details <a id="details" class="tall">&nbsp;</a> 
  
### Ingesting Tweet IDs <a id="ingesting-tweet-ids" class="tall">&nbsp;</a>

A first step for making Engagement API requests is compiling a collection of Tweet IDs. This client is designed to ingest Tweet IDs from several sources:

+ [Gnip Historical PowerTrack](http://support.gnip.com/apis/historical_api/) files. These JSON files can be gzipped or uncompressed.
+ JSON responses from either of Gnip's Search products: [30-Day](http://support.gnip.com/apis/search_api/) or [Full-Archive](http://support.gnip.com/apis/search_full_archive_api/).
+ Responses from the Twitter Public API<a id="twitter-public-endpoints" class="tall">&nbsp;</a>. Output from the following Public Endpoints have response formats that have been tested with this client: 
	+ [GET statuses/lookup](https://dev.twitter.com/rest/reference/get/statuses/lookup) 
	+ [GET statuses/user_timeline](https://dev.twitter.com/rest/reference/get/statuses/user_timeline)
	+ [GET search/tweets](https://dev.twitter.com/rest/reference/get/search/tweets)
+ Simple text files with one Tweet ID per line. Tweet IDs stored in a database can easily be exported into such a file.
    + Format example:
    ```
tweet_ids
663581045829144576
663194656000217088
662669822032011264
662432052344659968
662264949171965952
662244928261644291
662136102518697984
```

These file types are placed in a configured 'inbox' folder. After these files are ingested, then are moved into a 'processed' subfolder (automatically created if necessary).

#### Handling API Requests for Unowned Tweets <a id="unowned-tweets" class="tall">&nbsp;</a> 

If you submit a unowned Tweet ID (a Tweet that you do not have permission for), the Engagement API rejects the entire request, even if there are owned Tweet IDs in the request. This Client automatically strips those IDs from the request and resubmits the Tweet ID list containing only owned Tweets. 


### Client Output <a id="output" class="tall">&nbsp;</a> 

This client can output the series of Engagement API responses and also a 'Results' CSV file containing grand totals and a sorted 
list of Top Tweets: 

+ API responses are written to an ```api_responses``` outbox subfolder if the ```app_settings.yaml``` ```save_api_responses:``` option is set to true. [TODO] 
+ The CSV files are written to the 'outbox' folder indicated in the app_settings.yaml file. 

#### API Responses <a id="api-responses" class="tall">&nbsp;</a>

As the Client makes its series of API requests, it writes the API JSON responses to the ```[outbox]/[name]/metrics``` directory, where 

+ [outbox] is the output folder specified by the ```outbox:``` app setting. 
+ [name] is the dataset name specified by the ```name:``` app setting. 
+ These results files are numerically serialized as ```[name]_metrics.json```, ```[name]_metrics_1.json```, ```[name]_metrics_2.json```, etc. as necessary. 

#### Top Tweets <a id="top-tweets" class="tall">&nbsp;</a>

As this client makes its series of requests to the Engagement API, it aggregates grand totals for each Engagement type and 
compiles a list of 'top Tweets' for each Engagement Type indicated in the app_settings.yaml configuration file. The number of Top Tweets 
is specified in the ```app_settings.yaml``` file with the ```max_top_tweets:``` setting (defaults to 10, turn this processing off by setting to zero).

For example, if I process a collection of my recent Tweets, with these configuration details:

```
max_top_tweets: 1

engagement_types: 
  impressions: true
  engagements: true
  
engagement_groupings:
  by_tweet_type: 
    - tweet.id
    - engagement.type  

```

The following 'Top Tweets' JSON is generated:

```
{
  "top_tweets": [
    {
      "type": "impressions",
      "tweets": [
        {
          "id": "695310089847111681",
          "count": 415
        }
      ]
    },
    {
      "type": "engagements",
      "tweets": [
        {
          "id": "695310089847111681",
          "count": 28
        }
      ]
    }
  ],
  "totals": [
    {
      "type": "impressions",
      "count": 2519
    },
    {
      "type": "engagements",
      "count": 58
    }
  ]
}

```


As output the above JSON is formatted as a CSV file with sorted list with clickable links:



Engagement API Results

Number of Tweets: 320

Engagement Type,Total
Impressions,439709
Engagements,10

Top Tweets

Top Tweets for impressions:,impressions,Tweet links:
662136102518697984,27463,https://twitter.com/lookup/status/662136102518697984
662264949171965952,27462,https://twitter.com/lookup/status/662264949171965952
663194656000217088,27438,https://twitter.com/lookup/status/663194656000217088
662669822032011264,27414,https://twitter.com/lookup/status/662669822032011264
662432052344659968,27405,https://twitter.com/lookup/status/662432052344659968
662244928261644291,27394,https://twitter.com/lookup/status/662244928261644291
662135346604437504,27374,https://twitter.com/lookup/status/662135346604437504
661553916090392576,27370,https://twitter.com/lookup/status/661553916090392576
661385932080324608,27366,https://twitter.com/lookup/status/661385932080324608
661378873549053952,27365,https://twitter.com/lookup/status/661378873549053952

Top Tweets for engagements:,engagements,Tweet links:
662136102518697984,3,https://twitter.com/lookup/status/662136102518697984
663194656000217088,3,https://twitter.com/lookup/status/663194656000217088
663581045829144576,2,https://twitter.com/lookup/status/663581045829144576
649987151887667200,1,https://twitter.com/lookup/status/649987151887667200
662432052344659968,1,https://twitter.com/lookup/status/662432052344659968



### Specifying Start and End Times for Historical Requests <a id="specifying-times" class="tall">&nbsp;</a>

When accessing the ```/historical``` endpoint, if no "start" and "end" parameters are specified, the Engagement API defaults to the most recent 28 days. "Start" time defaults to 28 days ago from now, and "End" time default to "now". 

The Engagement API currently uses ISO #### date stamps for the ```/historical``` endpoint's ```start``` and ```end``` request parameters.
(Note: the client code is setup to support the Gnip date stamp format (```YYYMMDDHHMM```) in case the Engagement API works with that in the future.)  

Start and End times are specified using the UTC time standard. 

Start ```-s``` and end ```-e``` parameters can be specified in a variety of ways:

+ Standard Gnip PowerTrack format, YYYYMMDDHHmm (UTC)
	+ -s 201602010700 --> Metrics starting 2016-02-01 00:00 MST, ending 28 days later.
	+ -e 201602010700 --> Metrics ending 2016-02-01 00:00, starting 28 days earlier.

+ A combination of an integer and a character indicating "days" (#d), "hours" (#h) or "minutes" (#m). Some examples:
	+ -s 7d --> Start seven days ago (i.e., metrics from the last week).
	+ -s 14d -e 7d --> Start 14 days ago and end 7 days ago (i.e. metrics from the week before last).
	+ -s 6h --> Start six hours ago (i.e. metrics from the last six hours).

+ "YYYY-MM-DD HH:mm" (UTC, use double-quotes please).
	+ -s "2015-11-04 07:00" -e "2015-11-07 06:00" --> Metrics between 2015-11-04 and 2015-11-07 MST.

+ "YYYY-MM-DDTHH:MM:SS.000Z" (ISO 8061 timestamps as used by Twitter, in UTC)
	+ -s 2015-11-20T15:39:31.000Z --> Metrics beginning at 2015-11-20 22:00:00 MST .


### Code Details <a id="code-details" class="tall">&nbsp;</a>

There are four Ruby files associated with this client (subject to change due to refactoring and more attention to "separating concerns"): 
+ engagement_app.rb: <a id="engagement-app" class="tall">&nbsp;</a>
    + Creates one instance of the EngagementClient (engagement_client.rb) class. 
    + Manages configuration files, command-line options and application session logic. This app starts up, works through a 'session', then exits.
    + A 'session' consists of:
    	+ Parsing input files (Tweet collection or a simple ID list).
    	+ Manages as many API calls as neccessary by calling Engagement Client's `manage_process' method. 
    	+ Compiles Top Tweets as responses are received.
    	+ Generates a results summary.
    + Start here if you are adding/changing command-line details. 
    + No API requests are made directly from app. This app doesn't care how the HTTP details are implemented.

+ /lib/engagement_client.rb <a id="engagement-client" class="tall">&nbsp;</a>
    + The intent here is to have this class encapsulate all the low-level understanding of exercising the Engagement API.
    + Manages HTTP calls, OAuth, and generates all API request URLs.  
     
    + This class has the following constants. These are subject to change, so updates these as the API evolves:
        + MAX_TWEETS_PER_REQUEST_TOTALS = 250
        + MAX_TWEETS_PER_REQUEST_28HR = 25
        + MAX_TWEETS_PER_REQUEST_HISTORICAL = 25
        + TOTALS_ENGAGEMENT_TYPES = ['favorites', 'replies', 'retweets']
      
    + This class has and manages the following attributes:
        + A single array of Tweet IDs. (The insights_utils module knows the details of producing the array).   
        + HTTP endpoint details.
        + A single set of app keys and access tokens.
        + Settings that map to the app_settings.yaml file.

+ /common/insights_utils.rb <a id="insights-utils" class="tall">&nbsp;</a>
    + A 'utilities' helper class with methods common to both Insights APIs, Audience and Engagement.
    + Where all extacting of IDs happens... Adding a new Tweet/User IDs file type? Add a method here.
    + Code here is shared with other Insights API clients, such as the Audience API client.

+ /common/app_logger.rb <a id="app-logger" class="tall">&nbsp;</a>
    + A singleton module that provides a basic logger. The above scripts/classes reference the AppLogger module.
    + Provides a verbose mode where info and error log statements are printed to Standard Out.
    + Current logging signature: 
        + ```AppLogger.log_info("I have some information to share")```
        + ```AppLogger.log_error("An error occurred: #{error.msg}")```
    
        If you have in-house logger conventions to implement it should be pretty straightforward to swap that in.    


### License

Copyright 2017 Twitter, Inc. and contributors.

Licensed under the MIT License: https://opensource.org/licenses/MIT


