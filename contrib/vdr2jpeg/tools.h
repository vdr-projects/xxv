/*
 * Simple program to grab images from VDR Recording
 *
 * Copyright(c) 2007-2008 Andreas Brachold
 *
 * This code is distributed under the terms and conditions of the
 * GNU GENERAL PUBLIC LICENSE. See the file COPYING for details.
 *
 */

#include <string>
#include "ffm.h"

int option(int argc, char *argv[], const char opt, bool bParam,
    std::string & param, int n = 1);

// Helperclass for proper init/deinit ffmpeg
struct ffminit
{
    ffminit() { 
      ffm_initalize();    
    }

    virtual ~ffminit() { 
      ffm_deinitalize();   
    }
};



