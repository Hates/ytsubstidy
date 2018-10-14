require 'active_support/all'
require 'httparty'
require 'Oj'
require 'highline'
require 'byebug'

HEADERS = {
  'Authorization' => ENV['OAUTH_KEY']
}

DEFAULT_CUTOFF = 1.years.ago

def subscriptions(next_page_token = nil)
  items = []

  response = fetch_subscriptions(next_page_token)
  response = Oj.load(response.body)
  # puts ">>>>>>>>>>>>> #{response}'
  # puts ""
  # puts ""

  channel_ids = response['items'].map { |i| i['snippet']['resourceId']['channelId'] }.join(',')
  # puts ">>>>>>>>>>>> #{channel_ids}"
  # puts ""
  # puts ""

  channel_response = fetch_uploads_id(channel_ids)
  channel_response = Oj.load(channel_response.body)
  # puts ">>>>>>>>>>>>> #{channel_response}"
  # puts ""
  # puts ""

  items << response['items'].map do |item|
    playlist_id = nil
    last_upload = nil
    last_upload_title = nil

    id = item['id']
    channel_name = item['snippet']['title']
    channel_id = item['snippet']['resourceId']['channelId']

    begin
      channel = channel_response['items'].select { |c| c['id'] == channel_id }.first
      playlist_id = channel['contentDetails']['relatedPlaylists']['uploads']
    rescue
      puts ">>>> Could not fetch playlist date for #{channel_name}"
    end

    if playlist_id
      last_upload_response = fetch_last_upload(playlist_id)
      last_upload_response = Oj.load(last_upload_response.body)
      # puts ">>> #{last_upload_response}"

      last_upload = nil
      last_upload_title = nil

      begin
        last_upload = Date.parse(last_upload_response['items'][0]['snippet']['publishedAt'])
        last_upload_title = last_upload_response['items'][0]['snippet']['title']

        if last_upload < DEFAULT_CUTOFF
          puts ">>>> Old Channel #{channel_name} - #{last_upload}"
        end
      rescue
        puts ">>>> Could not fetch last upload date for #{channel_name}"
      end
    end

    {
      id: id,
      name: channel_name,
      channel_id: channel_id,
      playlist_id: playlist_id,
      last_upload: last_upload,
      last_upload_title: last_upload_title
    }
  end

  puts items

  next_page_token = response['nextPageToken']
  if next_page_token
    items = items + Array(subscriptions(next_page_token))
  end

  items
end

def fetch_subscriptions(page_token = nil)
  query = {
    'part' => 'snippet',
    'channelId' => 'UCprfVxQipXlbwmFxReQiOLQ',
    'maxResults' => 50,
    'pageToken' => page_token
  }

  HTTParty.get(
    'https://www.googleapis.com/youtube/v3/subscriptions',
    query: query,
    headers: HEADERS
  )
end

def fetch_uploads_id(channel_id)
  query = {
    'part' => 'contentDetails',
    'id' => channel_id
  }

  HTTParty.get(
    'https://www.googleapis.com/youtube/v3/channels',
    query: query,
    headers: HEADERS
  )
end

def fetch_last_upload(playlist_id)
  query = {
    'part' => 'snippet',
    'playlistId' => playlist_id
  }

  HTTParty.get(
    'https://www.googleapis.com/youtube/v3/playlistItems',
    query: query,
    headers: HEADERS
  )
end

def unsubscribe(subscription_id)
  query = {
    'id' => subscription_id
  }

  HTTParty.delete(
    'https://www.googleapis.com/youtube/v3/subscriptions',
    query: query,
    headers: HEADERS
  )
end
channels = subscriptions.flatten

potential_unsubscribes = channels.select { |c| c[:playlist_id].nil? } + channels.select { |c| c[:last_upload].nil? } + channels.select { |c| c[:last_upload] && c[:last_upload] < DEFAULT_CUTOFF }
potential_unsubscribes = potential_unsubscribes.uniq.flatten

puts '-------------------------------------------------------'

puts potential_unsubscribes

cli = HighLine.new
potential_unsubscribes.each do |sub|
  answer = cli.ask("Unsubscribe from #{sub}?  ") { |q| q.default = 'n' }
  next if answer != 'y'

  unsubscribe(sub[:id])
end
