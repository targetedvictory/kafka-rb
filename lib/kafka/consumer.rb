# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module Kafka
  class Consumer

    include Kafka::IO

    MAX_SIZE = 1024 * 1024        # 1 megabyte
    DEFAULT_POLLING_INTERVAL = 2  # 2 seconds
    MAX_OFFSETS = 1
    LATEST_OFFSET = -1
    EARLIEST_OFFSET = -2

    attr_accessor :topic, :partition, :offset, :max_size, :request_type, :polling

    def initialize(options = {})
      self.topic        = options[:topic]     || "test"
      self.partition    = options[:partition] || 0
      self.host         = options[:host]      || HOST
      self.port         = options[:port]      || PORT
      self.offset       = options[:offset]
      self.max_size     = options[:max_size]  || MAX_SIZE
      self.polling      = options[:polling]   || DEFAULT_POLLING_INTERVAL
      connect(host, port)
    end

    def loop(&block)
      messages = []
      while (true) do
        messages = consume
        block.call(messages) if messages && !messages.empty?
        sleep(polling)
      end
    end

    def consume
      self.offset ||= fetch_latest_offset
      send_consume_request
      message_set = Kafka::Message.parse_from(read_data_response)
      self.offset += message_set.size
      message_set.messages
    rescue SocketError
      nil
    end

    def fetch_latest_offset
      send_offsets_request(LATEST_OFFSET)
      read_offsets_response
    end

    def fetch_earliest_offset
      send_offsets_request(EARLIEST_OFFSET)
      read_offsets_response
    end

    def send_offsets_request(offset)
      write(encoded_request_size)
      write(encode_request(Kafka::RequestType::OFFSETS, topic, partition, offset, MAX_OFFSETS))
    end
    
    def read_offsets_response
      read_data_response[4,8].reverse.unpack('q')[0]
    end

    def send_consume_request
      write(encoded_request_size)
      write(encode_request(Kafka::RequestType::FETCH, topic, partition, offset, max_size))
    end

    def read_data_response
      data_length = read(4).unpack("N").shift
      data = read(data_length)
      # TODO: inspect error code instead of skipping it
      data[2, data.length]
    end

    def encoded_request_size
      size = 2 + 2 + topic.length + 4 + 8 + 4
      [size].pack("N")
    end

    def encode_request(request_type, topic, partition, offset, max_size)
      request_type = [request_type].pack("n")
      topic        = [topic.length].pack('n') + topic
      partition    = [partition].pack("N")
      offset       = [offset].pack("q").reverse # DIY 64bit big endian integer
      max_size     = [max_size].pack("N")
      request_type + topic + partition + offset + max_size
    end
  end
end
