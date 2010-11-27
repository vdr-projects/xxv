/*
 * Simple program to grab images from VDR Recording
 *
 * Copyright(c) 2010 Andreas Brachold
 *
 * This code is distributed under the terms and conditions of the
 * GNU GENERAL PUBLIC LICENSE. See the file COPYING for details.
 */
/*
   the demuxer is based on the original demuxer from mpeg2dec.c
    Copyright (C) 2000-2003 Michel Lespinasse <walken@zoy.org>
    Copyright (C) 1999-2000 Aaron Holtzman <aholtzma@ess.engr.uvic.ca>
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include "mpegdec.h"


#define DEMUX_HEADER 0
#define DEMUX_DATA 1
#define DEMUX_SKIP 2

#define DEMUX_PAYLOAD_START 1
#define DEMUX_RESET 2

static int state = DEMUX_SKIP;
static int state_bytes = 0;
static int demux_pid = 0;
static int demux_track = 0xE0;

void demux_reset(void)
{
	state = DEMUX_SKIP;
	state_bytes = 0;
  demux_pid = 0;
  demux_track = 0xE0;
}

static bool store_mpeg2 (unsigned char * current, unsigned char * end, const char* f)
{
  FILE * d;
  d = fopen (f, "ab");
  if (!d) {
    fprintf (stderr, "Could not open file \"%s\".\n", f);
    demux_reset();
    return false;
  }

  fwrite (current, 1, end-current, d);
  fclose (d);
  return true;
}


// from mpeg2dec.cpp
int demuxPES (unsigned char * buf, unsigned char * end, const char* f,  int flags)
{
	int iRet = 0;
  static int mpeg1_skip_table[16] =
  {
    0, 0, 4, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  };

  /*
   * the demuxer keeps some state between calls:
   * if "state" = DEMUX_HEADER, then "head_buf" contains the first
   *     "bytes" bytes from some header.
   * if "state" == DEMUX_DATA, then we need to copy "bytes" bytes
   *     of ES data before the next header.
   * if "state" == DEMUX_SKIP, then we need to skip "bytes" bytes
   *     of data before the next header.
   *
   * NEEDBYTES makes sure we have the requested number of bytes for a
   * header. If we dont, it copies what we have into head_buf and returns,
   * so that when we come back with more data we finish decoding this header.
   *
   * DONEBYTES updates "buf" to point after the header we just parsed.
   */


  static unsigned char head_buf[264];

  unsigned char * header;
  int bytes;
  int len;

#define NEEDBYTES(x)					\
  do {							\
    int missing;					\
                                                        \
    missing = (x) - bytes;				\
    if (missing > 0) {					\
      if (header == head_buf) {				\
        if (missing <= end - buf) {			\
          memcpy (header + bytes, buf, missing);	\
          buf += missing;				\
          bytes = (x);				        \
        } else {					\
          memcpy (header + bytes, buf, end - buf);	\
          state_bytes = bytes + end - buf;		\
          return iRet;					\
        }						\
      } else {						\
        memcpy (head_buf, header, bytes);		\
        state = DEMUX_HEADER;				\
        state_bytes = bytes;				\
        return iRet;					\
      }							\
    }							\
  } while (0)

#define DONEBYTES(x)		\
  do {		        	\
    if (header != head_buf)	\
      buf = header + (x);	\
  } while (0)

  if (flags & DEMUX_RESET)
  {
	  state = DEMUX_SKIP;
	  state_bytes = 0;
  }
  if (flags & DEMUX_PAYLOAD_START)
  {
    state = DEMUX_SKIP;
    goto payload_start;
  }
  switch (state)
  {
    case DEMUX_HEADER:
      if (state_bytes > 0)
      {
        header = head_buf;
        bytes = state_bytes;
        goto continue_header;
      }
    break;

    case DEMUX_DATA:
      if (demux_pid || (state_bytes > end - buf))
      {
        if(!store_mpeg2 (buf, end, f))
          if(state == DEMUX_SKIP)  return 0;
        state_bytes -= end - buf;
        return iRet;
      }
      if(!store_mpeg2 (buf, buf + state_bytes, f))
        if(state == DEMUX_SKIP)  return 0;
      buf += state_bytes;
    break;

    case DEMUX_SKIP:
    if (demux_pid || (state_bytes > end - buf))
    {
      state_bytes -= end - buf;
      return iRet;
    }
    buf += state_bytes;
    break;
  }

  while (1)
  {
    if (demux_pid)
    {
        state = DEMUX_SKIP;
        return iRet;
    }

    payload_start:
    header = buf;
    bytes = end - buf;

    continue_header:
    NEEDBYTES (4);
    if (header[0] || header[1] || (header[2] != 1))
    {
      if (demux_pid)
      {
      state = DEMUX_SKIP;
      return iRet;
      }
      else if (header != head_buf)
      {
      buf++;
      goto payload_start;
      }
      else
      {
        header[0] = header[1];
        header[1] = header[2];
        header[2] = header[3];
        bytes = 3;
        goto continue_header;
      }
    }
    if (demux_pid)
    {
      if ((header[3] >= 0xe0) && (header[3] <= 0xef))
        goto pes;
      fprintf (stderr, "bad stream id %x\n", header[3]);
      return -1;
    }
    switch (header[3])
    {
      case 0xb9:	/* program end code */
        /* DONEBYTES (4); */
        /* break;         */
        return 1;

      case 0xba:	/* pack header */
        NEEDBYTES (12);
      if ((header[4] & 0xc0) == 0x40)
      {	/* mpeg2 */
          NEEDBYTES (14);
          len = 14 + (header[13] & 7);
          NEEDBYTES (len);
          DONEBYTES (len);
          /* header points to the mpeg2 pack header */
      }
      else if ((header[4] & 0xf0) == 0x20)
      {	/* mpeg1 */
          DONEBYTES (12);
          /* header points to the mpeg1 pack header */
      }
      else
      {
          fprintf (stderr, "weird pack header\n");
          return -1;
        }
      break;

      case 0xbd:	// private stream 1
      case 0xc0:	// audio stream 0
        NEEDBYTES (9);
        len = header[4]*256+header[5]+6;
        NEEDBYTES(len);
        DONEBYTES(len);
      break;
    default:

      if (header[3] == demux_track)
      {
      pes:
        NEEDBYTES (7);
        if ((header[6] & 0xc0) == 0x80)
        {	/* mpeg2 */
          NEEDBYTES (9);
          len = 9 + header[8];
          NEEDBYTES (len);
        }
        else
        {	/* mpeg1 */
          int len_skip;
          len = 7;
          while (header[len - 1] == 0xff)
          {
            len++;
            NEEDBYTES (len);
            if (len == 23)
            {
              fprintf (stderr, "too much stuffing\n");
              break;
            }
          }
          if ((header[len - 1] & 0xc0) == 0x40)
          {
            len += 2;
            NEEDBYTES (len);
          }
          len_skip = len;
          len += mpeg1_skip_table[header[len - 1] >> 4];
          NEEDBYTES (len);
        }
        DONEBYTES (len);
        bytes = 6 + (header[4] << 8) + header[5] - len;
        if (demux_pid || (bytes > end - buf))
        {
          if(!store_mpeg2 (buf, end, f))
            if(state == DEMUX_SKIP)  return 0;
          state = DEMUX_DATA;
          state_bytes = bytes - (end - buf);
          return 0;
        }
        else if (bytes > 0)
        {
          if(!store_mpeg2 (buf, buf + bytes, f))
            if(state == DEMUX_SKIP)  return 0;
          buf += bytes;
        }
      }
      else if (header[3] < 0xb9)
      {
        fprintf (stderr, "looks like a video stream, not system stream\n");
        return -1;
      }
      else
      {
        //fprintf(stderr, "header[3] is %02X\n",header[3]);
        NEEDBYTES (6);
        DONEBYTES (6);
        bytes = (header[4] << 8) + header[5];
        //skip:
        if (bytes > end - buf)
        {
          state = DEMUX_SKIP;
          state_bytes = bytes - (end - buf);
          return iRet;
        }
        buf += bytes;
      }
    }
  }

  return iRet;
}

int demuxTS(unsigned char * buffer, unsigned char * end, const char* f,  int flags )
{
	unsigned char * buf;
	unsigned char * nextbuf;
	unsigned char * data;
	int pid;
	buf = buffer;
	int demuxflag = flags;
  int iRet = -1;

    int r = end - buf;
    int i = 0;
    while( i < r )
    {
      if (buf[i] != 0x47) 
      {
        fprintf (stderr, "bad sync byte\n");
        i++;
        continue;
      }
      demux_pid = ((buf[i+1] << 8) + buf[i+2]) & 0x1fff;
      i+=188;
    }

	for (; (nextbuf = buf + 188) <= end; buf = nextbuf) 
	{
		if (*buf != 0x47) 
		{
			fprintf (stderr, "bad sync byte\n");
			nextbuf = buf + 1;
			continue;
		}
		pid = ((buf[1] << 8) + buf[2]) & 0x1fff;
		if (pid != demux_pid)
			continue;
		data = buf + 4;
		if (buf[3] & 0x20) 
		{	// buf contains an adaptation field 
			data = buf + 5 + buf[4];
			if (data > nextbuf)
				continue;
		}
		if (buf[3] & 0x10)
		{
			if( (demuxflag & DEMUX_RESET) == DEMUX_RESET )
			{
				if( buf[1] & 0x40 )
				{
					iRet = demuxPES (data, nextbuf, f, DEMUX_PAYLOAD_START|demuxflag);
          if(state == DEMUX_SKIP)  return 0;
					demuxflag = 0;
				}
			}
			else
			{
				iRet = demuxPES (data, nextbuf, f, (buf[1] & 0x40) ? DEMUX_PAYLOAD_START|demuxflag : demuxflag);
        if(state == DEMUX_SKIP)  return 0;
				demuxflag = 0;
			}
		}
	}
	return iRet;
}
