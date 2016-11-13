require 'socket'
require 'ffi'

MPTCP_GET_SUB_IDS=66      # Get subflows ids
MPTCP_CLOSE_SUB_ID=67     # Close sub id
MPTCP_GET_SUB_TUPLE=68    # Get sub tuple
MPTCP_OPEN_SUB_TUPLE=69   # Open sub tuple
MPTCP_SUB_GETSOCKOPT=71   # Get sockopt for a specific sub
MPTCP_SUB_SETSOCKOPT=72   # Set sockopt for a specific sub

class SubStatus < FFI::Struct
  layout :id,         :uint8,
		     :low_prio,   :uint16 
end

class Subs < FFI::Struct
  layout :sub_count,  :uint8,
		     :sub_status, [SubStatus, 256]
  # Since we don't know the size of the array in advance, we just set it to
  # the maximum possible size, which is 2^8 (uint8).
end

def mptcp_get_sub_ids(sock)
  opt = sock.getsockopt(:IPPROTO_TCP, MPTCP_GET_SUB_IDS) 
  memBuf = FFI::MemoryPointer.new(Subs).put_bytes(0, opt.data)
  Subs.new(memBuf)
end

class MptcpCloseSubId < FFI::Struct
  layout  :id,  :uint8,
          :how, :int
end

def mptcp_close_sub_id(sock, id, how)
  opt_val = MptcpCloseSubId.new 
  opt_val[:id] = id
  opt_val[:how] = how
  sockopt = Socket::Option.new(
    :INET,
    :IPPROTO_TCP,
    MPTCP_CLOSE_SUB_ID, 
    opt_val.pointer.get_bytes(0, opt_val.size) # Verify this works?
  )
  # Ok, this is wrong as getsockopt does not accept a socket option obvioulsy...
  # Damn it -_-
  opt = sock.getsockopt(sockopt)
end

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
          :prio, :uint8,
          :addr1, MptcpSockaddrIn6,
          :addr2, MptcpSockaddrIn6
end

class MptcpSubTupleIn < FFI::Struct
  layout  :id,   :uint8,
          :prio, :uint8,
          :addr1, MptcpSockaddrIn,
          :addr2, MptcpSockaddrIn
end

sock = TCPSocket.new('192.168.99.100', 8000)
subs = mptcp_get_sub_ids(sock)
puts subs[:sub_count]
puts subs[:sub_status][0][:id]
mptcp_close_sub_id(sock, 1, 1)

