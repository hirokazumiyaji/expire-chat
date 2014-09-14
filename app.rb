require 'securerandom'
require 'sinatra'

configure do
  require 'redis'
  uri = ENV["REDISTOGO_URL"] || 'redis://127.0.0.1:6379'
  uri = URI.parse(uri)
  REDIS = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
end

class Room
  attr_reader :id

  def initialize(id: nil)
    @room_key_prefix = "chat:room"
    @id, @expire_at = get_id(id)
  end

  def remaining_time
    @expire_at
  end

  def create
    @id = gen_id()
    REDIS.setex("#{@room_key_prefix}#{@id}", 60 * 5, @id)
  end

  private
  def gen_id
    base_id = Time.now.utc.to_i.to_s
    key = "chat:room:ai:#{base_id}"
    auto_increment, _ = REDIS.pipelined do
      REDIS.incr(key)
      REDIS.expire(key, 1)
    end
    "#{base_id}#{auto_increment}"
  end

  def get_id(id)
    key = "#{@room_key_prefix}#{id}"
    REDIS.pipelined do
      REDIS.get(key)
      REDIS.ttl(key)
    end
  end
end

class Post
  attr_reader :message

  def initialize(id, message)
    @id = id
    @key = "chat:post:#{@id}"
    @message = message
  end

  def post
    REDIS.pipelined do
      REDIS.rpush(@key, @message)
      REDIS.expire(@key, 60 * 5)
    end
  end

  def Post.find_by(id)
    REDIS.lrange("chat:post:#{id}", 0, -1).map do |message|
      Post.new(id, message)
    end
  end
end

get '/' do
  erb :index
end

get '/chat/:room_id' do
  @room = Room.new(id: params[:room_id])
  redirect '/' if @room.id == nil
  @posts = Post.find_by(@room.id)
  erb :chat
end

post '/chat/create' do
  room = Room.new()
  room.create
  redirect "/chat/#{room.id}"
end

post '/chat/post' do
  room = Room.new(id: params[:room_id])
  redirect '/' if room.id == nil
  Post.new(room.id, params[:message]).post
  redirect "/chat/#{room.id}"
end

post '/chat/search' do
  room = Room.new(id: params[:room_id])
  redirect '/' if room.id == nil
  redirect "/chat/#{room.id}"
end
