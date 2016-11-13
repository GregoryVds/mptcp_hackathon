require 'socket'
require 'ffi'
require 'ipaddr'

module MPTCP
  extend FFI::Library
  TCP_PROTO_NUM=6
  
  AF_INET=2
  AF_INET6=10

  MPTCP_GET_SUB_IDS=66      # Get subflows ids
  MPTCP_CLOSE_SUB_ID=67     # Close sub id
  MPTCP_GET_SUB_TUPLE=68    # Get sub tuple
  MPTCP_OPEN_SUB_TUPLE=69   # Open sub tuple
  MPTCP_SUB_GETSOCKOPT=71   # Get sockopt for a specific sub
  MPTCP_SUB_SETSOCKOPT=72   # Set sockopt for a specific sub

  class SubStatus < FFI::Struct
    layout  :id,         :uint8,
            :low_prio,   :uint16 
  end

  class SubIds < FFI::Struct
    layout :sub_count,  :uint8,
           :sub_status, [SubStatus, 256]
    # Since we don't know the size of the array in advance, we just set it to
    # the maximum possible size, which is 2^8 (uint8).
  end

  def self.get_sub_ids(sock)
    # In this case, we can use the getsockopt method exposed by Ruby Socket 
    # class. No need to call underlying original C function.
    opt = sock.getsockopt(:IPPROTO_TCP, MPTCP_GET_SUB_IDS) 
    memBuf = FFI::MemoryPointer.new(SubIds).put_bytes(0, opt.data)
    SubIds.new(memBuf)
  end

  # Then, we can do:
  # subs = get_sub_ids(sock)
  # subs_count = subs[:sub_count]
  # sub1_id = subs[1][:id]

  ############################################################################

  class SockaddrIn < FFI::Struct
    layout  :sin_family,  :short,
            :sin_port,    :ushort,
            :sin_addr,    :ulong,
            :sin_zero,    [:char, 8]
  end

  class SockaddrIn6 < FFI::Struct
    layout  :sin6_family,   :uint16,
            :sin6_port,     :uint16,
            :sin6_flowinfo, :uint32,
            :sin6_addr,     [:uchar, 16],
            :sin6_scope_id, :uint32
  end

  class Sockaddr < FFI::Struct
    layout :sa_family, :ushort,
           :sa_data,   [:char, 14]
  end

  class SubTupleIn6 < FFI::Struct
    layout  :id,   :uint8,
            :addr1, SockaddrIn6,
            :addr2, SockaddrIn6
  end

  class SubTupleIn < FFI::Struct
    layout  :id,   :uint8,
            :addr1, SockaddrIn,
            :addr2, SockaddrIn
  end
 
  def self.open_subflow(sock, mptcp_sub_tuple)
    # In this case, we need to use the C getsockopt() function since the 
    # getsockopt() exposed by Ruby does not allow the optval to be passed as an
    # argument, but only returns an optval.
    setsockopt(
      sock.fileno,
      TCP_PROTO_NUM,
      MPTCP_OPEN_SUB_TUPLE,
      mptcp_sub_tuple.pointer,
      mptcp_sub_tuple.size
    ) 
  end
  
  ############################################################################

  ffi_lib 'c'
  attach_function :getsockopt, [ :int, :int, :int, :pointer, :pointer ], :int

  class MptcpCloseSubId < FFI::Struct
    layout  :id,  :uint8,
            :how, :int
  end

  class Socklen_t < FFI::Struct
    layout :val, :int
  end

  def self.close_subflow(sock, id, how)
    optval = MptcpCloseSubId.new 
    optval[:id] = id
    optval[:how] = how
    optlen = Socklen_t.new
    optlen[:val] = optval.size
    getsockopt(sock.fileno, TCP_PROTO_NUM, MPTCP_CLOSE_SUB_ID,
               optval.pointer, optlen.pointer)
  end

  
  ############################################################################  
    
  attach_function :inet_ntop, [ :int, :pointer, :pointer, :int], :pointer

  def self.print_inet(pointer)
      str = FFI::MemoryPointer.new(:char, 16)
      inet_ntop(AF_INET, pointer, str, 16)
      puts str.read_string
  
  end

  def self.get_sub_tuple(sock, id)
    # We pass a SubTupleIn6, which is the largest struct that could be
    # returned (the other option is SubTupleIn, with Ipv4 addresses).
    optval = SubTupleIn6.new
    optval[:id] = id
    socklen = Socklen_t.new
    socklen[:val] = optval.size 
    rc = getsockopt(
      sock.fileno,
      TCP_PROTO_NUM,
      MPTCP_GET_SUB_TUPLE,
      optval.pointer,
      socklen.pointer,
    )
    puts "Socklen: "+socklen[:val].to_s
    if rc == -1
      puts("MPTCP_GET_SUB_TUPLE failed.")
      return false
    end
    # At this point, the opval struct should be filled with sub_tuple info.
    addr1 = optval[:addr1]
    sockaddr = Sockaddr.new
    sockaddr.pointer.put_bytes(0, optval.pointer.get_bytes(1, sockaddr.size))

    if sockaddr[:sa_family] == AF_INET
      addr2 = SockaddrIn.new
      puts "size"+addr2.size.to_s
      addr1.pointer.put_bytes(0, optval.pointer.get_bytes(1, addr1.size))
      print_inet(addr1.pointer+4)

      addr2 = SockaddrIn.new
      addr2.pointer.put_bytes(0, optval.pointer.get_bytes(1+16, addr2.size))
      print_inet(addr2.pointer+4)
      
      puts addr1.pointer+2     
      puts addr2[:sin_port]
    elsif sockaddr[:sa_family] == AF_INET6
      puts("IPv6")
    else
      puts("Wrong sa_family")
      return false
    end
  end
end

sock = TCPSocket.new('192.168.99.100', 8000)
subs = MPTCP.get_sub_ids(sock)
puts subs[:sub_count]
puts subs[:sub_status][0][:id]
# puts MPTCP.close_subflow(sock, 1, 0)
pu:ts MPTCP.get_sub_tuple(sock, 1)
