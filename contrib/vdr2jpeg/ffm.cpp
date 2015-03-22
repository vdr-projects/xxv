/*
 * Simple program to grab images from VDR Recording
 *
 * Copyright (c) 2015 Andreas Brachold
 * 
 * This code is distributed under the terms and conditions of the
 * GNU GENERAL PUBLIC LICENSE. See the file COPYING for details.
 *
 */

#include <stdlib.h>
#include <iostream>
#include <sstream>
#include "ffm.h"

#define STRING(s) #s

#ifndef FFMPEG_BIN
#define FFMPEG_BIN "ffmpeg"
#endif

bool decode (const char* szMPVfile, /* const tPackedList & packed, */
             const char* szTmpMask, 
             int width, int height)
{

  int frame_width = 0;
  int frame_height = 0;
  int keep_aspect_ratio = 1;

#if 0
  std::cerr << "szMPVfile:" << szMPVfile << std::endl;
  std::cerr << "szTmpMask:" << szTmpMask << std::endl;
  std::cerr << "width:" << width << std::endl;
  std::cerr << "height:" << height << std::endl;
#endif

  if (width > 0 || height > 0) {
    if (width > 0) {
      frame_width = width;
          keep_aspect_ratio |= 1;
      } else {
          keep_aspect_ratio &= ~1;
      }

    if (height > 0) {
      frame_height = height;
          keep_aspect_ratio |= 2;
      } else {
          keep_aspect_ratio &= ~2;
      }
  }

  std::stringstream ss;
  ss << FFMPEG_BIN;

  ss << " -loglevel ";
#ifdef DEBUG
  ss << "verbose -report";
#else
  ss << "quiet";
#endif
  ss << " -an -i '" << szMPVfile << "'";

  if((keep_aspect_ratio & 2) == keep_aspect_ratio) { // Nur Höhe wurde definiert
    ss << " -vf scale=-1:" << frame_height;
  } else if((keep_aspect_ratio & 1) == keep_aspect_ratio) { // Nur Weite wurde definiert
    ss << " -vf scale=" << frame_width << ":-1";
  } else {
    ss << " -vf scale=" << frame_width << ":" << frame_height;
  }

  ss << " '" << szTmpMask << "'";
#ifdef DEBUG
  std::cerr << ss.str();
#endif

  return (0 == system(ss.str().c_str()));
}

