/*
 * Simple program to grab images from VDR Recording
 *
 * Copyright(c) 2010 Andreas Brachold
 *
 * This code is distributed under the terms and conditions of the
 * GNU GENERAL PUBLIC LICENSE. See the file COPYING for details.
 */

#ifndef __MPEGDEC_H__
#define __MPEGDEC_H__

void demux_reset(void);
int demuxPES (unsigned char * buf, unsigned char * end, const char* szFileName, int flags);
int demuxTS(unsigned char * buffer, unsigned char * end, const char* szFileName, int flags=0 );

#endif
