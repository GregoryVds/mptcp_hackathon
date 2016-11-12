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

sock = TCPSocket.new('192.168.99.100', 8000)
subs = mptcp_get_sub_ids(sock)
puts subs[:sub_count]
puts subs[:sub_status][0][:id]

