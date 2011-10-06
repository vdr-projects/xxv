/*
 * Simple program to grab images from VDR Recording
 *
 * Copyright(c) 2007-2008 Andreas Brachold
 *
 * This code is distributed under the terms and conditions of the
 * GNU GENERAL PUBLIC LICENSE. See the file COPYING for details.
 *
 */

#include <string.h>
#include "tools.h"

int option(int argc, char *argv[], const char opt, bool bParam,
    std::string & param, int n)
{
    for(int i = n; i < argc; ++i)
    {
        if(argv[i] && strlen(argv[i]) > 1)
        {
            switch(*(argv[i] + 0))
            {
                case '-':
                {
                    if(*(argv[i] + 1) == opt)
                    {
                        if(!bParam)
                            return i + 1;
                        if(i + 1 < argc)
                        {
                            param = argv[i + 1];
                            return i + 2;
                        }
                    }
                }
            }
        }
    }
    return -1;
}

