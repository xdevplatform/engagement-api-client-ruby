require 'oauth'
require 'zlib'
require 'stringio'
require 'json'

class EngagementClient
  def initialize
    @base_url = 'https://data-api.twitter.com'
    @service_path = '/insights/engagement/'
  end

  def set_keys(keys)
    @keys = keys
  end

  def get_api_access
    consumer = OAuth::Consumer.new(@keys['consumer_key'], @keys['consumer_secret'], {:site => @base_url})
    token = {:oauth_token => @keys['access_token'],
     :oauth_token_secret => @keys['access_token_secret']
    }

    @api = OAuth::AccessToken.from_hash(consumer, token)
  end

  def set_settings(settings)
    @endpoint = settings['engagement_settings']['endpoint'] #What endpoint are we hitting?

    @start_date = settings['engagement_settings']['start']
    @end_date = settings['engagement_settings']['end']

    @engagement_types = settings['engagement_types']
    @groupings = settings['engagement_groupings']
  end

  def create_request(tweets_of_interest)
    @request = {}
    @request['tweet_ids'] = tweets_of_interest

    if @endpoint == 'historical'
      @request['start'] = @start_date
      @request['end'] = @end_date
    end

    @request['engagement_types'] = @engagement_types
    @request['groupings'] = {}
    @groupings.each do |key, items|
      @request['groupings'][key] = {}
      @request['groupings'][key]['group_by'] = []
      items.each do |item|
        @request['groupings'][key]['group_by'] << item
      end
    end
  end

  def make_request
    get_api_access if @api.nil?

    uri_path = @base_url + @service_path + @endpoint
    result = @api.post(uri_path, @request.to_json, {"content-type" => "application/json", "Accept-Encoding" => "gzip"})
    gz = Zlib::GzipReader.new( StringIO.new( result.body ) )

    result.body = gz.read
    result.body = JSON.parse(result.body)

    result
  end
end
