/*
 * Simple program to grab images from VDR Recording
 *
 * Copyright (c) 2005-2008 Andreas Brachold
 *
 * This code is distributed under the terms and conditions of the
 * GNU GENERAL PUBLIC LICENSE. See the file COPYING for details.
 *
 */

extern void ffm_initalize(void);
extern void ffm_deinitalize(void);

extern bool decode(const char* szMPVfile,
                   const char* szTmpMask, int width, int height); 

