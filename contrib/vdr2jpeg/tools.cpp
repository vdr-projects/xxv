/*
 * Simple program to grab images from VDR Recording
 *
 * Copyright(c) 2007 Andreas Brachold
 *
 * This code is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 * 
 * This code is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 * Or, point your browser to http://www.gnu.org/copyleft/gpl.html
 */

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

