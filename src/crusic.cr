require "discordcr"
require "yaml"

# Reading config
CONFIG = YAML.parse(File.read("./config.yaml"))
# Prefixes
PREFIX = ["#{CONFIG["prefix"]}", "<@#{CONFIG["client_id"]}>", "<@#{CONFIG["client_id"]}> ", "<@!#{CONFIG["client_id"]}> ", "<@!#{CONFIG["client_id"]}>"]

VERSION = CONFIG["version"]

module Gayboard
  # Initialize bot
  BOT = Discord::Client.new(token: "Bot #{CONFIG["token"]}", client_id: CONFIG["client_id"].to_s.to_u64)

  # ## MOST OF THE CODE & COMMENTS IF FROM THE VOICE_SEND EXAMPLE HERE: https://github.com/meew0/discordcr/blob/master/examples/voice_send.cr ###

  # ID of the current user, required to create a voice client
  current_user_id = nil

  # The ID of the (text) channel in which the connect command was run, so the
  # "Voice connected." message is sent to the correct channel
  connect_channel_id = nil

  # Where the created voice client will eventually be stored
  voice_client = nil

  BOT.on_message_create do |payload|
    if PREFIX.any? { |p| payload.content.starts_with?("#{p}play") }
      # Check if dm
      next if payload.guild_id.is_a?(Nil)
      # Args
      args = payload.content.gsub("#{PREFIX[1]} ", "#{PREFIX[1]}").gsub("#{PREFIX[3]} ", "#{PREFIX[3]}").split(" ")
      # Remove prefix+command
      args.shift
      # Get guild's channels
      channels = BOT.get_guild_channels(payload.guild_id.not_nil!)
      voice_channel_id = ""
      # Embed
      correct_format_embed = Discord::Embed.new(
        colour: 0xeb2d3a,
        title: "Usage: #{PREFIX[0]}play [channel_name or mention] <url>"
      )
      # Check how many args are there
      if args.size == 2
        # Check if its an id
        match = "#{args[0]}".match(/[0-9]+/)
        if match && match.size == 1
          voice_channel_id = match[0].to_u64
        else
          # if not check by name
          channels.each do |channel|
            next unless channel.type.guild_voice?
            next unless channel.name.not_nil!.downcase == "#{args[0].downcase}"
            voice_channel_id = channel.id
          end
        end
      elsif args.size == 1
        # if none of the above, go with "music"
        channels.each do |channel|
          next unless channel.type.guild_voice?
          next unless channel.name.not_nil!.downcase == "music"
          voice_channel_id = channel.id
        end
      else
        next BOT.create_message(payload.channel_id, "", correct_format_embed)
      end
      # if no channels found
      next BOT.create_message(payload.channel_id, "", correct_format_embed) if voice_channel_id == ""

      connecting_embed = Discord::Embed.new(
        colour: 0xfb654e,
        title: "Connecting to #{voice_channel_id} ..."
      )
      # connect to za voice channel
      main_msg = BOT.create_message(payload.channel_id, "", connecting_embed)
      connect_channel_id = payload.channel_id
      BOT.voice_state_update(payload.guild_id.not_nil!.to_u64, voice_channel_id.not_nil!.to_s.to_u64, false, false)

      url = ""

      not_a_url = Discord::Embed.new(
        colour: 0xeb2d3a,
        title: "You didn't provide a valid url",
        description: "Usage: #{PREFIX[0]}play [channel_name or mention] <url>\nOr create a voice channel named \"Music\""
      )
      # same as the previous but now we are checking for urls
      if args.size == 2
        match = "#{args[1]}".match(/[-a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,6}\b([-a-zA-Z0-9@:%_\+.~#?&\/\/=]*)/)
        if match
          url = match[0]
        else
          BOT.edit_message(payload.channel_id, main_msg.id, "", not_a_url)
          next
        end
      elsif args.size == 1
        match = "#{args[0]}".match(/[-a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,6}\b([-a-zA-Z0-9@:%_\+.~#?&\/\/=]*)/)
        if match
          url = match[0]
        else
          BOT.edit_message(payload.channel_id, main_msg.id, "", not_a_url)
          next
        end
      end

      next BOT.edit_message(payload.channel_id, main_msg.id, "", not_a_url) if url == ""
      begin_download_embed = Discord::Embed.new(
        colour: 0xadd8e6,
        title: "Download started!"
      )

      begin_downalod_msg = BOT.edit_message(payload.channel_id, main_msg.id, "", begin_download_embed)
      # get current unixms
      current_unix_ms = Time.utc.to_unix_ms
      # run yt-dl
      ytdl_cmd = "youtube-dl -x --audio-format opus --output './src/music/#{current_unix_ms}.%(ext)s' #{url}"
      Process.run(ytdl_cmd, shell: true)
      download_embed = Discord::Embed.new(
        colour: 0x90ee90,
        title: "Download completed!\nConverting to DCA started!"
      )

      downalod_msg = BOT.edit_message(payload.channel_id, begin_downalod_msg.id, "", download_embed)
      # convert to dca
      ffmpeg_cmd = "ffmpeg -i ./src/music/#{current_unix_ms}.opus -f s16le -ar 48000 -ac 2 pipe:1 | dca > ./src/music/#{current_unix_ms}.dca"
      Process.run(ffmpeg_cmd, shell: true)
      # remove opus
      File.delete("./src/music/#{current_unix_ms}.opus")
      finished_embed = Discord::Embed.new(
        colour: 0x90ee90,
        title: "Converting to DCA completed!\nStarting streaming!"
      )

      finished_msg = BOT.edit_message(payload.channel_id, downalod_msg.id, "", finished_embed)
      # lets open the dca
      file = File.open("./src/music/#{current_unix_ms}.dca")
      # lets parse it
      parser = Discord::DCAParser.new(file, true)
      # send speaking
      voice_client.not_nil!.send_speaking(true)

      # send packets every 20ms till no frames left
      Discord.every(20.milliseconds) do
        frame = parser.next_frame(reuse_buffer: true)
        break unless frame

        # Perform the actual sending of the frame to Discord.
        voice_client.not_nil!.play_opus(frame)
      end

      file.close
      # delete dca
      File.delete("./src/music/#{current_unix_ms}.dca")
    end
  end

  BOT.on_voice_server_update do |payload|
    begin
      vc = voice_client = Discord::VoiceClient.new(payload, BOT.session.not_nil!, current_user_id.not_nil!)
      vc.run
    rescue e
      e.inspect_with_backtrace(STDOUT)
    end
  end

  # Ready event
  BOT.on_ready do |things|
    current_user_id = things.user.id
    # Guild count
    servers = things.guilds.size
    # Change status every 1 min
    Discord.every(60000.milliseconds) do
      stats = [
        "discord.gg/SWEsj6q",
        "geopjr.xyz",
      ]
      BOT.status_update("online", Discord::GamePlaying.new(name: "#{stats.sample} | #{servers} servers", type: 3_i64))
    end
  end
  BOT.run
end
