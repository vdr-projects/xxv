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

#ifndef FFMPEG_BIN
#define FFMPEG_BIN "ffmpeg"
#endif

bool decode (const char* szMPVfile,
             const char* szTmpMask, 
             int width, int height)
{

#if 0
  std::cerr << "szMPVfile:" << szMPVfile << std::endl;
  std::cerr << "szTmpMask:" << szTmpMask << std::endl;
  std::cerr << "width:" << width << std::endl;
  std::cerr << "height:" << height << std::endl;
#endif

  std::stringstream ss;
  ss << FFMPEG_BIN;

  ss << " -loglevel ";
#ifdef DEBUG
  ss << "verbose -report";
#else
  ss << "error";
#endif
  ss << " -an -i '" << szMPVfile << "'";

  if(width > 0 && height > 0) {
    ss << " -vf 'scale=" << width << ":ih*" << height << "/iw'";
  } else if(height > 0) { // Nur Höhe wurde definiert
    ss << " -vf 'scale=iw*trunc(oh*a/2)*2/ih:" << height << "'";
  } else if(width > 0) { // Nur Weite wurde definiert
    ss << " -vf 'scale=" << width << ":ih*trunc(ow/a/2)*2/iw'";
  }

  ss << " '" << szTmpMask << "'";
#ifdef DEBUG
  std::cerr << ss.str() << std::endl;
#endif

  return (0 == system(ss.str().c_str()));
}

