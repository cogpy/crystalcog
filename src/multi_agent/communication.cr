# Multi-Agent Communication for CrystalCog
#
# This module implements message passing and communication protocols
# between agents in a multi-agent system.

require "../cogutil/cogutil"

module MultiAgent
  module Communication
    VERSION = "0.1.0"

    class CommunicationException < Exception
    end

    # FIPA-inspired performatives
    enum Performative
      INFORM
      REQUEST
      QUERY
      REPLY
      PROPOSE
      ACCEPT
      REJECT
      SUBSCRIBE
      CANCEL
    end

    # A message exchanged between agents
    struct Message
      getter id : String
      getter sender : String
      getter receiver : String
      getter performative : Performative
      getter content : String
      getter timestamp : Time
      getter in_reply_to : String?
      getter conversation_id : String

      def initialize(
        @sender : String,
        @receiver : String,
        @performative : Performative,
        @content : String,
        @conversation_id : String = "",
        @in_reply_to : String? = nil,
      )
        @id = Random::Secure.hex(8)
        @timestamp = Time.utc
        @conversation_id = @conversation_id.empty? ? @id : @conversation_id
      end

      def reply(sender : String, performative : Performative, content : String) : Message
        Message.new(
          sender: sender,
          receiver: @sender,
          performative: performative,
          content: content,
          conversation_id: @conversation_id,
          in_reply_to: @id
        )
      end

      def to_s : String
        "[#{@id[0, 6]}] #{@sender}->#{@receiver} (#{@performative}): #{@content}"
      end
    end

    # A mailbox that stores incoming messages for an agent
    class Mailbox
      getter agent_id : String
      getter messages : Array(Message)

      def initialize(@agent_id : String)
        @messages = [] of Message
      end

      def deliver(message : Message)
        @messages << message
      end

      def has_messages? : Bool
        !@messages.empty?
      end

      def next_message : Message?
        @messages.shift?
      end

      def messages_from(sender : String) : Array(Message)
        @messages.select { |m| m.sender == sender }
      end

      def unread_count : Int32
        @messages.size
      end
    end

    # Message bus: routes messages between agents
    class MessageBus
      getter mailboxes : Hash(String, Mailbox)

      def initialize
        @mailboxes = {} of String => Mailbox
        @history = [] of Message
        CogUtil::Logger.info("MessageBus initialized")
      end

      def register(agent_id : String)
        @mailboxes[agent_id] = Mailbox.new(agent_id)
        CogUtil::Logger.debug("Agent '#{agent_id}' registered on message bus")
      end

      def deregister(agent_id : String)
        @mailboxes.delete(agent_id)
      end

      def send(message : Message) : Bool
        mailbox = @mailboxes[message.receiver]?
        unless mailbox
          CogUtil::Logger.warn("Unknown receiver: #{message.receiver}")
          return false
        end
        mailbox.deliver(message)
        @history << message
        CogUtil::Logger.debug("Delivered: #{message}")
        true
      end

      def broadcast(sender : String, performative : Performative, content : String)
        @mailboxes.each_key do |id|
          next if id == sender
          msg = Message.new(sender, id, performative, content)
          send(msg)
        end
      end

      def mailbox_for(agent_id : String) : Mailbox?
        @mailboxes[agent_id]?
      end

      def history : Array(Message)
        @history.dup
      end
    end
  end
end
