module Ricer4::Connectors
  class Websocket < Ricer4::Connector

    def protocol; server.tls? ? 'wssl' : 'ws'; end

    def connect!
      EM.run {
        
        bot.log.info("EM::WebSocket.run(#{server.url})")
        @connected = true
        server.set_online(true)

        EM::WebSocket.run(:host => server.hostname, :port => server.port) do |ws|
          
          ws.onopen { |handshake|
            bot.log.info("Websocket.onopen(#{handshake})")
          }
          
          ws.onclose {
            bot.log.info("Websocket.onclose()")
            if ws.instance_variable_defined?(:@ricer_user)
              user = ws.remove_instance_variable(:@ricer_user)
              xlin_logout(user)
            end
          }
          
          ws.onmessage { |msg|
  
            arm_signal(server, "ricer/incoming", msg)
  
            if msg.length == 0
              #bot.log.debug("empty line: #{msg}")
            elsif ws.instance_variable_defined?(:@ricer_user)
              user = ws.instance_variable_get(:@ricer_user)
              message = Ricer4::Message.new
              message.raw = msg
              message.prefix = user.hostmask
              message.type = 'privmsg'
              message.args = [user.name, msg]
              message.server = server
              message.sender = user
              message.target = bot
              #arm_signal(server, "ricer/receive", message)
              #arm_signal(server, "ricer/received", message)
              arm_signal(server, "ricer/messaged", message)
            else
              xlin_login(ws, msg)
            end
          }
        end
      }
      @connected = false
      server.set_online(false)
      bot.log.info("EM::WebSocket.stop(#{server.url})")
    end
    
    def xlin_logout(user)
      user.logout!
      user.set_online(false)
      if user.instance_variable_defined?(:@websocket)
        ws = user.remove_instance_variable(:@websocket)
        ws.close
      end
    end
    
    def xlin_hostmask(ws)
      handler = ws.instance_variable_get(:@handler)
      connection = handler.instance_variable_get(:@connection)
      port, ip = Socket.unpack_sockaddr_in(connection.get_peername)
      "#{user.name}!#{@ip}@websocket.ricer4"
    end

    def xlin_login(ws, line)
      if line.start_with?('xlin ')
        args = line.split(' ')
        unless user = websocket_xlin(args[1], args[2])
          ws.send('403: Auth failure!')
        else
          ws.instance_variable_set(:@ricer_user, user)
          user.instance_variable_set(:@websocket, ws)
          user.hostmask = xlin_hostmask(ws)
          ws.send('200: Authenticated!')
        end
      else
        ws.send('401: Not authenticated')
      end
    end

    def websocket_xlin(nickname, password)
      unless user = get_user(server, nickname)
        user = create_user(server, nickname)
        user.permissions = Ricer4::Permission::AUTHENTICATED.bit
        user.password = password
      else
        return nil unless user.authenticate!(password)
      end
      user.login!
      user
    end
    
    ################
    ### Messages ###
    ################
    def send_quit(line)
      send_to_all(line)
      server.users.online.each do |user|
        xlin_logout(user)
      end
      EM.stop
    end
    
    def send_to_all(line)
      server.users.online.each do |user|
        ws = user.instance_variable_get(:@websocket)
        ws.send(line)
      end
    end
    
    def send_reply(reply)
      arm_signal(server, "ricer/outgoing", reply.text)
      ws = reply.target.instance_variable_get(:@websocket)
      ws.send(reply.text)
    end
    
  end
end
