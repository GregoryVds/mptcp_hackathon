require 'socket'
require 'ffi'

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

  class Subs < FFI::Struct
    layout :sub_count,  :uint8,
           :sub_status, [SubStatus, 256]
    # Since we don't know the size of the array in advance, we just set it to
    # the maximum possible size, which is 2^8 (uint8).
  end

  def self.get_sub_ids(sock)
    # In this case, we can use the getsockopt method exposed by Ruby Socket 
    # class. No need to call underlying original C function.
    opt = sock.getsockopt(:IPPROTO_TCP, MPTCP_GET_SUB_IDS) 
    memBuf = FFI::MemoryPointer.new(Subs).put_bytes(0, opt.data)
    Subs.new(memBuf)
  end

  ############################################################################

  class MptcpSockaddrIn < FFI::Struct
    layout  :sin_family,  :short,
            :sin_port,    :ushort,
            :sin_addr,    :ulong,
            :sin_zero,    [:char, 8]
  end

  class MptcpSockaddrIn6 < FFI::Struct
    layout  :sin6_family,   :uint16,
            :sin6_port,     :uint16,
            :sin6_flowinfo, :uint32,
            :sin6_addr,     [:uchar, 16],
            :sin6_scope_id, :uint32
  end

  class MptcpSockaddr < FFI::Struct
    layout :sa_family, :ushort,
           :sa_data,   [:char, 14]
  end

  class MptcpSubTupleIn6 < FFI::Struct
    layout  :id,   :uint8,
            :addr1, MptcpSockaddrIn6,
            :addr2, MptcpSockaddrIn6
  end

  class MptcpSubTupleIn < FFI::Struct
    layout  :id,   :uint8,
            :addr1, MptcpSockaddrIn,
            :addr2, MptcpSockaddrIn
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
  
  def self.get_sub_tuple(sock, id)
    # We pass a MptcpSubTupleIn6, which is the largest struct that could be
    # returned (the other option is MptcpSubTupleIn, with Ipv4 addresses).
    optval = MptcpSubTupleIn6.new
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
    if rc == -1
      puts("MPTCP_GET_SUB_TUPLE failed.")
      return false
    end
    # At this point, the opval struct should be filled with sub_tuple info.
    addr1 = optval[:addr1]
    sockaddr = MptcpSockaddr.new
    sockaddr.pointer.put_bytes(0, optval.pointer.get_bytes(1, sockaddr.size))
    puts "Size:"+sockaddr.size.to_s
    puts "Flowid:"+optval[:id].to_s
    puts "sa_family"+sockaddr[:sa_family].to_s
    puts "Sin_family"+optval[:addr1][:sin6_family].to_s
  end

end


sock = TCPSocket.new('192.168.99.100', 8000)
subs = MPTCP.get_sub_ids(sock)
puts subs[:sub_count]
puts subs[:sub_status][0][:id]
# puts MPTCP.close_subflow(sock, 1, 0)
puts MPTCP.get_sub_tuple(sock, 1)
