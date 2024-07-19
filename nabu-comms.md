# NABU HCCA application communication protocol

The original NABU network adapter provided a unidirectional connection
from the headend system to the NABUs.  Each NABU could access the
software that was periodically broadcast through the cable network,
but they could not send any data back to the headend.

With the new surge of interest in the NABU PC, the original network
adapter has been replaced by virtual network adapters running on a
local system (i.e. a PC running Windows or Linux, or an embedded
system).  With these network adapters, bidirectional communication
through the network adapter interface is possible and opens up the
possiblity of using the NABU as an internet terminal or providing
network based storage services to applications running on the NABU.

This document proposes a unified protocol to be implemented by network
adapters to support NABU applications.

## Communication interface

The NABU HCCA serial interface is an asynchronous RS422 port running
at ~111860 bits per second using 8 bits per character, no parity and
one stop bit.  As the bitrate of the interface does not match any of
the standard baud rates provided by serial interfaces on modern
computers, network adapters usually use the standard 115200 bps baud
rate with two stop bits.  While this is slightly too fast, it matches
close enough for both sides to be able to read the bytes coming from
the other end.

Despite the historical origins with the NABU system, this protocol does
not specify, and is independent of, the physical transport used.  While
serial connections are certainly expected to be used with this protocol,
any stream-oriented transport may be used including, but not limited to,
non-serial I/O mapped hardware devices and stream-oriented network protocols,
such as TCP/IP.

## Message framing

The original network adapter protocol did not have any message
framing.  Each message that was exchanged with between the NABU and
the adapter had its specific length and response requirements.  This
protocol is not easy to extend, and as such does not form a good basis
for functionality proposed in this document.  NHACP, on the other hand,
uses a message framing mechanism that simplifies message transmission
and reception, greatly extends the number of available message types,
allows for independent operating system and application NHACP sessions
with the network adapter, and also allows both NHACP and non-NHACP
communication to co-exist between the client and the network adapter.

Historical note: The original NHACP draft, referred to as version 0.0
in this document, required the client application and the network adapter
to enter "NHACP mode".  Network adapters MAY support this mode for backwards
compatibility with existing applications.

All communication in the protocol is initiated by the NABU side.  The
NABU sends a request message which is responded to by the network adapter
with exactly one response message.  The NABU MUST NOT send another
request until it has received a response for the previous request.  For
real-time communication applications in which messages are sent to the NABU
through e.g. a network service, the network adapter must buffer these
messages until the NABU requests to see them.

Messages must be completely transmitted within one second.  This is intended
to reduce error recovery time.  As such, there is a hard ceiling on the
maximum transmission unit, dictacted by the NABU hardware.  With the native
tramission rate of 111860 bits per second and many network adapter
implementations using 2 stop bits (for a total of 11 bits per byte), 10169
bytes is the practical limit that can be transmitted within the allotted time.

The NHACP protocol specifies a maximum data payload of 8192 bytes and a
maximum transmission unit of 8256 bytes, thus allowing for 64 bytes of
framing and message structures.

Before any NHACP messages can be exchanged, a session must be established.
Establishing a session is done using the HELLO request.

Request messages and response messages both share a common format:

| Name     | Type | Notes                                             |
|----------|------|---------------------------------------------------|
| length   | u16  | Number of bytes that follow length field          |
| type     | u8   | Type of message                                   |
| contents | *    | Message contents (0 .. (8253 - check size) bytes) |
| check    | *    | Optional error check field                        |

All values are exchanged using the little-endian byte order.  Thus, a
16-bit number 0xaa00 is transmitted as the two bytes 0x00 and 0xaa.

In general, request message types (NABU -> network adapter) fall into
the range of 0x00 - 0x7f (MSB is zero) and response message types (network
adapter -> NABU) fall into the range 0x80 - 0xff (MSB is one), with one
exception: the GOODBYE message has the type 0xef.

The layout of the message contents depends on the message type.  The length
field indicates the number of message bytes that follow the length field;
because the message type always follows the length field, the smallest valid
value for the length field is 1.

Additional error detection features, described below, may be enabled when an
NHACP session is established using the options field in the HELLO message.

In order to interoperate with other NABU network adapter protocols and to
multiplex NHACP sessions, request messages are preceeded by two additional
request header bytes:

| Name          | Type | Notes                                                        |
|---------------|------|--------------------------------------------------------------|
| NHACP-REQUEST | u8   | 0x8f                                                         |
| session_id    | u8   | From SESSION-STARTED response; See HELLO request description |

If the client sends a request with an unknown session ID, the server MUST
return an ERROR response with the error code ESRCH.

If the CRC8 option is enabled in the HELLO request, then all NHACP messages
(including the HELLO request) have a 1-byte CRC-8/CDMA2000 appended to the end
of the message.  This byte MUST be counted in the length field of the message.
For request messages, the CRC calculation includes the request header.
If the CRC8 option is enabled and the CRC field is zero, then then the CRC
was not computed and the packet MUST NOT be rejected by the receiver due
to a CRC failure.  If CRC error detection is enabled, the network adapter
MUST compute the CRC for frames sent to the receiver.  Client applications
MAY choose to ignore CRC at any time.

The receiver MUST ignore partial or corrupted (if checked) messages and
SHOULD signal an error to the operator if it detects the timeout condition.

A conforming NHACP network adapter MUST obey the following rules when
receiving and sending messages:

* When receiving requests, extra bytes sent by the client application
  beyond the request arguments, so long as they are accounted for in
  the frame length field and CRC computation, MUST be allowed and
  not considered an error.
* When sending responses to the client application, the server MUST NOT
  send any extra bytes beyond those required to respond to the request.

Historical note: In NHACP-0.0, the NABU application switched to the NHACP
protocol by sending a single byte 0xaf to the network adapter.  Unfortunately,
there were several issues with this approach:

* The message byte 0xaf later collided with a different NABU network adapter
  protocol extension and there was no simple way to distinguish between
  the NHACP start-up message and message from the other protocol extension.
* The message had no way to convey any protocol versioning to the server.
* There was no way for the client application to enable optional behavior.
* The protocol was modal and did not support multiple sessions; only NHACP
  messages could be exchanged, and only one application at a time could
  exchange them.  The connection would be in NHACP mode until the application
  sent an END-PROTOCOL request.
* The modal behavior complicated client reboot detection and recovery.

## Error handling

For requests that can return an error, there is a well-defined set of
error codes with standard meanings.  See the ERROR response below.

Historical note: In NHACP-0.0, the ERROR response could have returned a
detailed error message in every response.  However, this requires that
applications always have a buffer large enough to receive this error
response (which was over 256 bytes in length).

To address this concern, the behavior (but not the format) of the ERROR
response has been changed to only include the fixed-sized portions of
the response in the default ERROR response.  This allows requests that
can return an ERROR response to have a buffer as small as 4 bytes to
receive the initial error indication.  A new GET-ERROR-DETAILS request
has been added for applications that wish to get detailed error information.
See the GET-ERROR-DETAILS request below.

## Protocol versioning

This document describes version **0.1** of the protocol.  This
section describes the changes between protocol revisions.  New
revisions are backward-compatible with previous clients, to the
extent possible; any possible compatibility issues are called out
explicitly here.

* Version 0.1
    * Defined the protocol versioning convention.
    * Defined the new NHACP-REQUEST session mutiplexing scheme and
      HELLO and SESSION-STARTED messages.
    * Defined the initial set of error codes.
    * Defined new ERROR response behavior and GET-ERROR-DETAILS request.
    * Defined the new STORAGE-GET-BLOCK and STORAGE-PUT-BLOCK requests.
    * Added section about complex aggregate types, and added definitions
      for the DATE-TIME, FILE-ATTRS, and STRING structures.
    * Redefined messages containing strings to use the new STRING
      structure.  Layout of those messages is backwards-compatible.
    * Redefined the DATE-TIME response message to use the DATE-TIME structure.
      Layout of the message is backwards-compatible.
    * Defined the new UINT8-VALUE, UINT16-VALUE, and UINT32-VALUE responses.
    * Defined the new FILE-READ, FILE-WRITE, FILE-SEEK, FILE-GET-INFO, and
      FILE-SET-SIZE requests, and FILE-INFO response.
    * Defined the new LIST-DIR and GET-DIR-ENTRY requests.
    * Defined the new REMOVE, RENAME, and MKDIR requests.
    * Renamed STORAGE-CLOSE to FILE-CLOSE.  The semantics of the operation
      are unchanged.
    * Added the optional CRC-8/CDMA2000 error detection.
* Version 0.0 - Initial version

The HELLO request and the SESSION-STARTED respose each include a 16-bit
unsigned integer that encodes the protocol version supported by the client
application and the network adapter, respectively.  These values are directly
arithmetically comparable, and is intended to make protocol version checking
simple for the client.  As a convention, the "major" and "minor" versions of
the protocol are kept in the most-significant and last-significant 8 bits of
the version field, respectively.  However, this is merely a convention and
the version values defined here are authoritative:

| Value  | Protocol version    |
|--------|---------------------|
| 0x0000 | initial NHACP draft |
| 0x0001 | NHACP version 0.1   |

Historical note: NHACP-0.0's initial response, NHACP-STARTED, included
a version field in the response which was not well-defined and, by
convention, network adapters filled this field with the value 0x0000.
This value MUST NOT be used by a client application to establish a new
NHACP session using the HELLO request.  If a client attempts to do so,
the network adapter MUST return an ERROR response with the error code
EINVAL.

Network adapters MAY wish to support the original 0xaf message type for
NHACP; such a server MUST maintain compatibility with the original draft
specification if this message is used to start NHACP.  If the client
attempts to enter NHACP-0.0 mode while other NHACP sessions are established,
the network adapter MUST ignore the request; the modal nature of NHACP-0.0
would necessarily starve the other NHACP sessions of access to the
network adapter.

## Complex aggregate types

In addition to the simple scalar types (u8, u16, u32) and simple aggregate
types (byte arrays), there are some complex aggregate types used in NHACP
that are shared by multiple request/response messages.

### DATE-TIME structure

| Name | Type    | Notes                           |
|------|---------|---------------------------------|
| date | char[8] | Current date in YYYYMMDD format |
| time | char[6] | Current time in HHMMSS format   |

### FILE-ATTRS structure

| Name      | Type      | Notes                       |
|-----------|-----------|-----------------------------|
| mtime     | DATE-TIME | Last file modification time |
| flags     | u16       | File attribute flags        |
| file-size | u32       | File size                   |

The following file attribute flags are defined.  All other flags are
reserved.

| Name | Value  | Notes                    |
|------|--------|--------------------------|
| RD   | 0x0001 | File is readable         |
| WR   | 0x0002 | File is writable         |
| DIR  | 0x0004 | File is a directory      |
| SPEC | 0x0008 | File is a "special" file |

A "special" file is a file that is not a regular file nor a directory.

### STRING structure

| Name   | Type  | Notes                                  |
|--------|-------|----------------------------------------|
| length | u8    | Total length of the string bytes field |
| bytes  | char* | String bytes                           |

The length field of a STRING defines the length of the bytes field.
Client applications MAY early-terminate the string using a 0-byte;
if a client application does so, the network adapter MUST consider
only the bytes preceeding the 0-byte when using the string.  The
length field MUST be used to locate additional message fields that
follow the STRING field.  In order to reduce computational complexity
in client applications when processing responses, network adapters
MUST NOT early-terminate strings with a 0-byte.

---

## Request messages

### HELLO

Establish a new NHACP session.

| Name    | Type    | Notes                          |
|---------|---------|--------------------------------|
| type    | u8      | 0x00                           |
| magic   | char[3] | "ACP"                          |
| version | u16     | Version number of the protocol |
| options | u16     | Protocol options               |

Possible responses: SESSION-STARTED, ERROR

When establishing a new session, the session ID from the request header
is examined to determine what kind of session to create.  The following
are the only valid session ID values in a HELLO request:

| Name   | Value | Notes                         |
|--------|-------|-------------------------------|
| SYSTEM | 0x00  | Establish the SYSTEM session  |
| CREATE | 0xff  | Create an application session |

The system session is intended to be used by the client operating system
software (e.g. the CP/M BIOS) to provide system services and is treated
specially; when the SYSTEM session is established, any previous sessions
associated with this client connection are closed and their resources freed.
This is done under the assumption that if a client is establishing the
system session, it has rebooted and thus no longer has any knowledge of
those previous sessions.  The network adapter MUST support the system session,
and MUST assign the system session the session ID 0.

If an application session is requested, the network adapter MAY allocate the
necessary context data and assign it a session ID in the range 1 .. 254.
Network adapters MUST support at least one application sesssion.

In either case, the session ID is returned to the client in the
SESSION-STARTED response.  This session ID MUST be used by the
requesting client in subsequent NHACP requests.

If the client specifies any other session ID with a HELLO request, the
network adapter MUST return an ERROR response with the error code EINVAL.
If all of the available sessions on the network adapter are in-use, then
the network adapter MUST return an ERROR response with the error code
ENSESS.

If the magic field of the HELLO request is not the 3-byte sequence "ACP",
then the network adapter SHOULD ignore the request, as it may not be a
NHACP HELLO request at all.

The following options are defined:

| Name | Value  | Notes                              |
|------|--------|------------------------------------|
| CRC8 | 0x0001 | Enable CRC-8/CDMA2000 error detection |

All other option bits are reserved.

If the client requests an NHACP version greater than that supported by
the network adapter or if the client requests an option not recognized
or not supported by the network adapter, then the network adapter MUST
return an ERROR response with the error code ENOTSUP.

### STORAGE-OPEN

Open a URL and assign a file descriptor to it.  The URL can be relative
or a file URL to open a local file.  Network adapters may implement
additional, nonstandard URL schemes.  Relative URLs are interpreted 
as files.  The flags field can be used to pass additional information
to the storage handler.  The meaning of the flags is not specified in
the protocol itself.

The network adapter will attempt to use the file descriptor specified by
the caller unless the caller specifies 0xff, in which case the network
adapter will attempt to allocate a file descriptor.  If the requested
file descriptor is already in-use by another file object, the STORAGE-OPEN
request MUST return an ERROR response with the error code EBUSY.

| Name      | Type   | Notes                                                              |
|-----------|--------|--------------------------------------------------------------------|
| type      | u8     | 0x01                                                               |
| req-fdesc | u8     | Requested file descriptor to use (0xff => Network Adapter selects) |
| flags     | u16    | Open flags                                                         |
| url       | STRING | URL / file name string                                             |

Possible responses: STORAGE-LOADED, ERROR

The following flags are defined:

| Name        | Value  | Notes                                                           |
|-------------|--------|-----------------------------------------------------------------|
| O_RDONLY    | 0x0000 | Open only for reading.                                          |
| O_RDWR      | 0x0001 | Open for reading + writing                                      |
| O_RDWP      | 0x0002 | RDWR + lazy write-protect                                       |
| O_DIRECTORY | 0x0008 | If set, object must be a directory, else must be a regular file |
| O_CREAT     | 0x0010 | Create the file if it does not exist                            |
| O_EXCL      | 0x0020 | Return an error if the file already exists                      |
| O_TRUNC     | 0x0040 | Truncate existing file to length 0                              |

All other flag values are reserved.

The least significant 3 bits of the flags field define the access
mode.  Thus, the values O_RDONLY, O_RDWR, and O_RDWP are part of
an enumeration and are mutually-exclusive with one another.

If O_EXCL is specified and the O_CREAT flag is not specified, then
the O_EXCL flag MUST be ignored.

If O_TRUNC is specified and the storage object is opened with read-only
access, then the O_TRUNC flag MUST be ignored.

If a read-only storage object is opened with O_RDWR, then the network
adapter MUST return an ERROR response with the error code EACCES.

O_RDWP is intended to mimic a write-protected floppy disk; if a read-only
storage object is opened with O_RDWP the open MUST succeed, but any
attempt to write to or otherwise modify the object MUST return an EROFS
error.

While NHACP-0.0 had space allocated in the STORAGE-OPEN request for flags,
it did not define any flags.  Network adapters that support NHACP-0.0
SHOULD ignore the flags field and assume O_RDWP+O_CREAT for NHACP-0.0
sessions.

If a non-seekable storage object (for example, a regular file accessed
using HTTP) is opened with the STORAGE-OPEN request, the network adapter
MUST buffer that object locally such that random access to the object
using the STORAGE-GET and STORAGE-GET-BLOCK requests is possible.  The
network adapter SHOULD treat such objects as read-only.

If the length of the URL string is 0, the network adapter MUST interpret
the request as a request to open the top-level directory.  The usual rules
for opening directories apply; the client MUST also specify the O_DIRECTORY
flag in the request.

### STORAGE-GET

Get data from network adapter storage.

The maximum data length for a STORAGE-GET is 8192 bytes.  Network
adapters MUST return an ERROR response with error code EINVAL for
STORAGE-GET requests whose length field exceeds this value.

| Name   | Type | Notes                            |
|--------|------|----------------------------------|
| type   | u8   | 0x02                             |
| fdesc  | u8   | File descriptor to access        |
| offset | u32  | Offset into the storage in bytes |
| length | u16  | Number of bytes to return        |

Possible responses: DATA-BUFFER, ERROR

The length returned in the DATA-BUFFER response reflects
the amount of data actuallty read from the underlying
file object.  If the offset is beyond the object's
end-of-file, then the returned length MUST be 0.
If the read operation would cross the object's end-of-file,
then the length MUST be the number of bytes read before
the end-of-file was encountered.

If the underlying file object cannot be accessed at arbitrary offsets,
the network adapter MUST return an ERROR response with the error code
ESEEK.

### STORAGE-PUT

Update data stored in the network adapter.  If possible, the
underlying storage (file/URL) should be updated as well.

The maximum data lengtyh for a STORAGE-PUT is 8192 bytes.  Network
adapters MUST return an ERROR response with error code EINVAL for
STORAGE-PUT requests whose length field exceeds this value.

| Name   | Type | Notes                            |
|--------|------|----------------------------------|
| type   | u8   | 0x03                             |
| fdesc  | u8   | File descriptor to access        |
| offset | u32  | Offset into the storage in bytes |
| length | u16  | Number of bytes to write         |
| data   | u8*  | Data to update the storage with  |

Possible responses: OK, ERROR

If a write originates at or beyond the underlying file
object's end-of-file or therwise crosses the end-of-file,
then the underlying file object SHOULD be implicitly
enlarged to accommodate the write.  For writes that originate
beyond end-of-file, the region between the old end-of-file and
the newly-written region MUST be implicitly zero-filled.  If
a server implementation does not support extending the underlying
file object, then the server MUST return an ERROR response with
the error code ENOTSUP without performing the write operation.

Errors are returned with the following priority:

* If the underlying file object was not opened with write access, then
  STORAGE-PUT MUST fail with an EBADF error.
* If the underlying file object cannot be accessed at arbitrary offsets,
  then STORAGE-PUT MUST fail with an ESEEK error.
* Other implementation-defined error conditions.

### GET-DATE-TIME

Retrieve the current date and time from the network adapter.

| Name | Type | Notes |
|------|------|-------|
| type | u8   | 0x04  |

Possible responses: DATE-TIME, ERROR

### FILE-CLOSE

Close a previously opened file descriptor.  Any resources associated with
it on the network adapter will be freed.

| Name  | Type | Notes                    |
|-------|------|--------------------------|
| type  | u8   | 0x05                     |
| fdesc | u8   | File descriptor to close |

No response message is returned by the network adapter.  If the server
receives a file descriptor that is not currently in use by the client,
the request is simply ignored.

### GET-ERROR-DETAILS

Request details for the most recent ERROR response from the network
adapter.

| Name            | Type | Notes                                           |
|-----------------|------|-------------------------------------------------|
| type            | u8   | 0x06                                            |
| code            | u16  | Last error code returned by the network adapter |
| max-message-len | u8   | Maximum message length to return                |

Possible responses: ERROR

A network adapter MAY choose to remember the last error returned to an
application, in which case if the error code in the request matches the
saved error code, a detailed description of the error will be returned
to the application.  If the network adapter does not remember the last
error returned to an application, or if the error code does not match
the last remembered error code, then the network adapter MUST return
a generic error description string for the error code in the request.
In either case, any saved error code is cleared.

### STORAGE-GET-BLOCK

Get a block of data from network adapter storage.  This is an optimization
of STORAGE-GET designed to support block-device storage.  Rather than a
byte offset and length, a block number and block length is specified.  The
byte offset into network adapter storage is computed by the network
adapter as:

	offset = block-number * block-length

STORAGE-GET-BLOCK operates on atomic units; partial reads MUST be zero-padded
to the block size.  Reads that originate beyond the end-of-file MUST result
in 0 bytes being returned.

The maximum data length for a STORAGE-GET-BLOCK is 8192 bytes.  Network
adapters MUST return an ERROR response with error code EINVAL for
STORAGE-GET requests whose length field exceeds this value.

| Name         | Type | Notes                            |
|--------------|------|----------------------------------|
| type         | u8   | 0x07                             |
| fdesc        | u8   | File descriptor to access        |
| block-number | u32  | 0-based index of block to access |
| block-length | u16  | Length of the block              |

Possible responses: DATA-BUFFER, ERROR

The length returned in the DATA-BUFFER response MUST equal the block size
in the request.

If the underlying file object cannot be accessed at arbitrary offsets,
then STORAGE-GET-BLOCK MUST fail with an ESEEK error.

### STORAGE-PUT-BLOCK

Put a block of data to network adapter storage.  This is an optimization
of STORAGE-PUT designed to support block-device storage.  Rather than a
byte offset and length, a block number and block length is specified.  The
byte offset into network adapter storage is computed by the network
adapter as:

	offset = block-number * block-length

The maximum data lengtyh for a STORAGE-PUT-BLOCK is 8192 bytes.  Network
adapters MUST return an ERROR response with error code EINVAL for
STORAGE-PUT requests whose length field exceeds this value.

| Name         | Type | Notes                            |
|--------------|------|----------------------------------|
| type         | u8   | 0x08                             |
| fdesc        | u8   | File descriptor to access        |
| block-number | u32  | 0-based index of block to access |
| block-length | u16  | Length of the block              |
| data         | u8*  | Data to update the storage with  |

Possible responses: OK, ERROR

If a write originates at or beyond the underlying file
object's end-of-file or therwise crosses the end-of-file,
then the underlying file object SHOULD be implicitly
enlarged to accommodate the write.  For writes that originate
beyond end-of-file, the region between the old end-of-file and
the newly-written region MUST be implicitly zero-filled.  If
a server implementation does not support extending the underlying
file object, then the server MUST return an ERROR response with
the error code ENOTSUP without performing the write operation.

Errors are returned with the following priority:

* If the underlying file object was not opened with write access, then
  STORAGE-PUT-BLOCK MUST fail with an EBADF error.
* If the underlying file object cannot be accessed at arbitrary offsets,
  then STORAGE-PUT-BLOCK MUST fail with an ESEEK error.
* Other implementation-defined error conditions.

### FILE-READ

Read data sequentially from a file descriptor.

The maximum payload langth for a FILE-READ is 8192 bytes.  Network
adapters MUST return an error for FILE-READ requests whose length
field exceeds this value.

| Name   | Type | Notes                     |
|--------|------|---------------------------|
| type   | u8   | 0x09                      |
| fdesc  | u8   | File descriptor to access |
| flags  | u16  | Flags                     |
| length | u16  | Number of bytes to return |

Possible responses: DATA-BUFFER, ERROR

There are no flags currently defined for FILE-READ; all values are
reserved.

The length returned in the DATA-BUFFER response reflects
the amount of data actuallty read from the underlying
file object.  If the file cursor is beyond the object's
end-of-file, then the returned length MUST be 0.
If the read operation would cross the object's end-of-file,
then the length MUST be the number of bytes read before
the end-of-file was encountered.

### FILE-WRITE

Perform a sequential write to a file descriptor.  If possible, the
underlying storage (file/URL) should be updated as well.

The maximum payload langth for a FILE-WRITE is 8192 bytes.  Network
adapters MUST return an error for FILE-WRITE requests whose length
field exceeds this value.

| Name   | Type | Notes                           |
|--------|------|---------------------------------|
| type   | u8   | 0x0a                            |
| fdesc  | u8   | File descriptor to access       |
| flags  | u16  | Flags                           |
| length | u16  | Number of bytes to write        |
| data   | u8*  | Data to update the storage with |

Possible responses: OK, ERROR

There are no flags currently defined for FILE-WRITE; all values are
reserved.

If the position of the file cursor causes the write to originate at or
beyond the underlying file object's end-of-file or therwise crosses
the end-of-file, then the underlying file object SHOULD be implicitly
enlarged to accommodate the write.  For writes that originate beyond
end-of-file, the region between the old end-of-file and the newly-written
region MUST be implicitly zero-filled.  If a server implementation does
not support extending the underlying storage object, then the server MUST
return an error without performing the write operation.

Errors are returned with the following priority:

* If the underlying file object was not opened with write access, then
  FILE-WRITE MUST fail with an EBADF error.
* Other implementation-defined error conditions.

### FILE-SEEK

Re-position the file cursor by a signed offset relative to the specified
seek origin.

| Name   | Type | Notes                          |
|--------|------|--------------------------------|
| type   | u8   | 0x0b                           |
| fdesc  | u8   | File descriptor to access      |
| offset | s32  | Offset relative to seek origin |
| whence | u8   | The origin of the seek         |

Possible responses: UINT32-VALUE, ERROR

The following whence values are defined:

| Name      | Value | Notes                                                    |
|-----------|-------|----------------------------------------------------------|
| SEEK_SET  | 0x00  | Set the cursor to offset bytes.                          |
| SEEK_CUR  | 0x01  | Set the cursor to the current location plus offset bytes |
| SEEK_END  | 0x02  | Set the cursor to the size of the file plus offset bytes |

Once the cursor has been repositioned, FILE-SEEK returns the resulting offset
measured in bytes from the beginning of the file.

If the underlying file object does not have a cursor that can be respositioned,
then FILE-SEEK MUST fail with an ESEEK error.

### FILE-GET-INFO

Get the attributes of the file associated with a file descriptor.

| Name   | Type | Notes                     |
|--------|------|---------------------------|
| type   | u8   | 0x0c                      |
| fdesc  | u8   | File descriptor to access |

Possible responses: FILE-INFO, ERROR

In the FILE-INFO response, the network adapter MUST set the length
of the name string to 0 and omit the file name.

### FILE-SET-SIZE

Set the size of a file associated with a file descriptor.  If the new
size is larger than the current size of the underlying storage object,
then the network adapter MUST zero-fill the region between the old
end-of-file and the new end-of-file.

| Name  | Type | Notes                     |
|-------|------|---------------------------|
| type  | u8   | 0x0d                      |
| fdesc | u8   | File descriptor to access |
| size  | u32  | New file size             |

Possible responses: OK, ERROR

### LIST-DIR

This request causes the network adapter to scan a directory for file names
matching the specified pattern, retrieve the attributes of those files,
and cache a list of those files to be retrieved one file at a time by future
requests.  The directory must have already been opened.  Any cached listing
is released upon a subsequent LIST-DIR or FILE-CLOSE request for that
file descriptor.

| Name    | Type   | Notes                                |
|---------|--------|--------------------------------------|
| type    | u8     | 0x0e                                 |
| fdesc   | u8     | File descriptor of directory to list |
| pattern | STRING | File name matching pattern           |

Possible responses: OK, ERROR

If the length of the pattern string is 0, then the network adapter MUST
list the entire directory.  Otherwise, the network adapter MUST list
only entries matching the specified pattern.  The network adapter SHOULD
implement pattern matching compatible with the glob() function specified
by IEEE Std 1003.2.

### GET-DIR-ENTRY

Returns the next directory entry cached by a LIST-DIR request and
advances the directory cursor.

| Name            | Type  | Notes                                             |
|-----------------|-------|---------------------------------------------------|
| type            | u8    | 0x0f                                              |
| fdesc           | u8    | File descriptor of directory that has been listed |
| max-name-length | u8    | Maximum length of the returned file name          |

Possible responses: OK, FILE-INFO, ERROR

If there are no more entries to return, or if the listing has not been
generated, the server MUST repond with OK to indicate the end-of-directory.

The name of the file in the returned directory entry MUST be truncated to
the max-name-length specifed by the application.

### REMOVE

Remove the specified file or directory.  If removing a directory, the
directory must be empty.

| Name  | Type   | Notes                             |
|-------|--------|-----------------------------------|
| type  | u8     | 0x10                              |
| flags | u16    | Flags                             |
| url   | STRING | URL / file name of file to remove |

Possible responses: OK, ERROR

The following flags are defined:

| Name        | Value  | Notes                              |
|-------------|--------|------------------------------------|
| REMOVE_FILE | 0x0000 | Psuedo-flag; remove a regular file |
| REMOVE_DIR  | 0x0001 | Remove a directory                 |

### RENAME

Rename and/or re-parent the specified file or directory.  If there is
a file object already residing at the new name, it must be of the same
object type (file or directory) as the object being renamed and it will
be removed as if with REMOVE.  While network adapter implementations
SHOULD make a best-effort to ensure the atomicity of the RENAME operation,
it is not guaranteed; a RENAME operation over an existing file object MAY
result in that object being removed even if the rename itself fails.

| Name    | Type   | Notes               |
|---------|--------|---------------------|
| type    | u8     | 0x11                |
| old-url | STRING | Old name / location |
| new-url | STRING | New name / location |

Possible responses: OK, ERROR

### MKDIR

Create a directory at the specified location.

| Name | Type   | Notes      |
|------|--------|------------|
| type | u8     | 0x12       |
| url  | STRING | URL string |

Possible responses: OK, ERROR

### GOODBYE

End an NHACP session.  If the session ID specifies the SYSTEM session,
then all NHACP sessions will be ended.  This is done under the assumption
that the operating system is performing an orderly shutdown.

| Name | Type | Notes |
|------|------|-------|
| type | u8   | 0xEF  |

No response message is returned by the network adapter.  If the GOODBYE
request arrives with an unknown session ID, the network adapter MUST ignore
the request.

---

## Response messages

Type tags in response messages have their MSB set.  Their numbering
must be consecutive to support fast dispatching on the type byte.

### SESSION-STARTED

| Name              | Type   | Notes                          |
|-------------------|--------|--------------------------------|
| type              | u8     | 0x80                           |
| session_id        | u8     | Session ID of the new session  |
| version           | u16    | Version number of the protocol |
| adapter-id        | STRING | Adapter identification string  |

If the client specified the SYSTEM session in the HELLO request, then
the network adapter MUST return the SYSTEM session ID in the SESSION-STARTED
response.

Historical note: This message uses the same type code as the NHACP-0.0
NHACP-STARTED message, which has a similar format, but lacks the session_id
field.

### OK

| Name | Type | Notes |
|------|------|-------|
| type | u8   | 0x81  |

### ERROR

| Name           | Type   | Notes         |
|----------------|--------|---------------|
| type           | u8     | 0x82          |
| code           | u16    | Error code    |
| message        | STRING | Error message |

In an ERROR response to any request other than GET-ERROR-DETAILS,
the network adapter MUST set the length of the message string to 0
and omit the detailed error message.

The following error codes are defined:

| Name      | Value | Notes                             |
|-----------|-------|-----------------------------------|
| undefined | 0     | undefined generic error           |
| ENOTSUP   | 1     | Operation is not supported        |
| EPERM     | 2     | Operation is not permitted        |
| ENOENT    | 3     | Requested file does not exist     |
| EIO       | 4     | Input/output error                |
| EBADF     | 5     | Bad file descriptor               |
| ENOMEM    | 6     | Out of memory                     |
| EACCES    | 7     | Access denied                     |
| EBUSY     | 8     | File is busy                      |
| EEXIST    | 9     | File already exists               |
| EISDIR    | 10    | File is a directory               |
| EINVAL    | 11    | Invalid argument/request          |
| ENFILE    | 12    | Too many open files               |
| EFBIG     | 13    | File is too large                 |
| ENOSPC    | 14    | Out of space                      |
| ESEEK     | 15    | Seek on non-seekable file         |
| ENOTDIR   | 16    | File is not a directory           |
| ENOTEMPTY | 17    | Directory is not empty            |
| ESRCH     | 18    | No such process or session        |
| ENSESS    | 19    | Too many sessions                 |
| EAGAIN    | 20    | Try again later                   |
| EROFS     | 21    | Storage object is write-protected |

All other error codes are reserved.

### STORAGE-LOADED

| Name   | Type | Notes                                         |
|--------|------|-----------------------------------------------|
| type   | u8   | 0x83                                          |
| fdesc  | u8   | File descriptor that was provided or selected |
| length | u32  | Length of the underlying storage object       |

### DATA-BUFFER

| Name   | Type | Notes            |
|--------|------|------------------|
| type   | u8   | 0x84             |
| length | u16  | Length of data   |
| data   | u8*  | Data from buffer |

### DATE-TIME

| Name      | Type      | Notes                 |
|-----------|-----------|-----------------------|
| type      | u8        | 0x85                  |
| date_time | DATE-TIME | Current date and time |

### FILE-INFO

| Name        | Type       | Notes           |
|-------------|------------|-----------------|
| type        | u8         | 0x86            |
| attrs       | FILE-ATTRS | File attributes |
| name        | STRING     | File name       |

### UINT8-VALUE

| Name  | Type | Notes               |
|-------|------|---------------------|
| type  | u8   | 0x87                |
| value | u8   | Generic 8-bit value |

### UINT16-VALUE

| Name  | Type | Notes                |
|-------|------|----------------------|
| type  | u8   | 0x88                 |
| value | u16  | Generic 16-bit value |

### UINT32-VALUE

| Name  | Type | Notes                |
|-------|------|----------------------|
| type  | u8   | 0x89                 |
| value | u32  | Generic 32-bit value |

### FILE-ATTRS

| Name        | Type       | Notes           |
|-------------|------------|-----------------|
| type        | u8         | 0x8a            |
| attrs       | FILE-ATTRS | File attributes |

---

## Recovering from a crash

When a NABU application crashes while NHACP sessions are active, the
network adapter needs to detect that the NABU is restarting.  Network
adapter implementations MUST end all NHACP sessions in a manner that
is equivelent to handling a GOODBYE request with the SYSTEM session ID
if the network adapter receives the 0x83 (START-UP) message from the
NABU.

Historical note: Because NHACP-0.0 was modal, network adapters needed
to watch for the most significant byte of an NHACP length frame containing
the value 0x83, or, more loosely, watch for the most significant bit of
the length field being set.  While this worked well enough, it complicated
error recovery and placed additional constraints on non-NABU adopters of
the NHACP protocol.  If a network adapter chooses to support the NHACP-0.0
version of the protocol, it MUST use the same crash detection logic for
NHACP-0.0 sessions and exit back into classic mode.

## Example exchanges

The following are examples of NHACP request / response exchanges.
Double-quotes denote non-NUL-terminated ASCII strings, which are
used for readability.

### Establishing an NHACP system session

| Application   | Network Adapter        |
|---------------|------------------------|
| 0x8f          |                        |
| 0x00 [SYSTEM] |                        |
| 0x08 0x00     |                        |
| 0x00 [HELLO]  |                        |
| "ACP"         |                        |
| 0x01 0x00     |                        |
| 0x00 0x00     |                        |
|               | 0x15 0x00              |
|               | 0x80 [SESSION-STARTED] |
|               | 0x00                   |
|               | 0x01 0x00              |
|               | 0x10                   |
|               | "NABU-ADAPTOR-1.1"     |

### Establishing an NHACP application session

| Application   | Network Adapter        |
|---------------|------------------------|
| 0x8f          |                        |
| 0xff [CREATE] |                        |
| 0x08 0x00     |                        |
| 0x00 [HELLO]  |                        |
| "ACP"         |                        |
| 0x01 0x00     |                        |
| 0x00 0x00     |                        |
|               | 0x15 0x00              |
|               | 0x80 [SESSION-STARTED] |
|               | 0x01                   |
|               | 0x01 0x00              |
|               | 0x10                   |
|               | "NABU-ADAPTOR-1.1"     |

### Opening a 1KB file, reading 1KB of data from offset 0, closing the file

| Application         | Network Adapter       |
|---------------------|-----------------------|
| 0x8f                |                       |
| 0x01                |                       |
| 0x0f 0x00           |                       |
| 0x01 [STORAGE-OPEN] |                       |
| 0xff                |                       |
| 0x00 0x00           |                       |
| 0x0a                |                       |
| "LEVEL1.DAT"        |                       |
|                     | 0x06 0x00             |
|                     | 0x83 [STORAGE-LOADED] |
|                     | 0x00                  |
|                     | 0x00 0x04 0x00 0x00   |
| 0x8f                |                       |
| 0x01                |                       |
| 0x08 0x00           |                       |
| 0x02 [STORAGE-GET]  |                       |
| 0x00                |                       |
| 0x00 0x00 0x00 0x00 |                       |
| 0x00 0x04           |                       |
|                     | 0x03 0x04             |
|                     | 0x84 [DATA-BUFFER]    |
|                     | 0x00 0x04             |
|                     | <1024 bytes of data>  |
| 0x8f                |                       |
| 0x01                |                       |
| 0x02 0x00           |                       |
| 0x05 [FILE-CLOSE]   |                       |
| 0x00                |                       |

### Opening a 1KB file, reading 1KB of data using sequential read, closing the file

| Application         | Network Adapter       |
|---------------------|-----------------------|
| 0x8f                |                       |
| 0x01                |                       |
| 0x0f 0x00           |                       |
| 0x01 [STORAGE-OPEN] |                       |
| 0xff                |                       |
| 0x00 0x00           |                       |
| 0x0a                |                       |
| "LEVEL1.DAT"        |                       |
|                     | 0x06 0x00             |
|                     | 0x83 [STORAGE-LOADED] |
|                     | 0x00                  |
|                     | 0x00 0x04 0x00 0x00   |
| 0x8f                |                       |
| 0x01                |                       |
| 0x06 0x00           |                       |
| 0x09 [FILE-READ]    |                       |
| 0x00                |                       |
| 0x00 0x04           |                       |
|                     | 0x03 0x04             |
|                     | 0x84 [DATA-BUFFER]    |
|                     | 0x00 0x04             |
|                     | <1024 bytes of data>  |
| 0x8f                |                       |
| 0x01                |                       |
| 0x02 0x00           |                       |
| 0x05 [FILE-CLOSE]   |                       |
| 0x00                |                       |

### Opening a file, error return, getting error details

| Application              | Network Adapter                    |
|--------------------------|------------------------------------|
| 0x8f                     |                                    |
| 0x00 [SYSTEM]            |                                    |
| 0x0a 0x00                |                                    |
| 0x01 [STORAGE-OPEN]      |                                    |
| 0xff                     |                                    |
| 0x00 0x00                |                                    |
| 0x05                     |                                    |
| "C.DSK"                  |                                    |
|                          | 0x04 0x00                          |
|                          | 0x82 [ERROR]                       |
|                          | 0x04 0x00                          |
|                          | 0x00                               |
| 0x8f                     |                                    |
| 0x00 [SYSTEM]            |                                    |
| 0x04 0x00                |                                    |
| 0x06 [GET-ERROR-DETAILS] |                                    |
| 0x04 0x00                |                                    |
| 0x40                     |                                    |
|                          | 0x24 0x00                          |
|                          | 0x82 [ERROR]                       |
|                          | 0x04 0x00                          |
|                          | 0x20                               |
|                          | "C.DSK: no such file or directory" |

### CRC-8/CDMA2000 Test Vectors

* "The quick brown fox jumps over the lazy dog."
    * Length: 44
    * CRC: 0xbc
* "NABU HCCA application communication protocol"
    * Length: 44
    * CRC: 0x53
