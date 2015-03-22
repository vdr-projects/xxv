/*
 * Simple program to grab images from VDR Recording
 *
 * Copyright(c) 2005-2010 Andreas Brachold
 *
 * This code is distributed under the terms and conditions of the
 * GNU GENERAL PUBLIC LICENSE. See the file COPYING for details.
 *
 */

#include <sys/types.h>
#include <sys/stat.h>       
#include <fcntl.h>
#include <stdlib.h>
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <algorithm>
#include "tools.h"
#include "ffm.h"
#include "gop.h"

static const char *VERSION        = "0.2.0";

void help(int argc, char *argv[])
{
    std::cerr << "Usage: " << argv[0] << " (" << VERSION << ")" << std::endl;
    std::cerr << "            -r recordings    : VDR recording folder" <<    std::endl;
    std::cerr << "            -f frame         : wanted frame (resolution at PAL - 1/25s)" <<    std::endl;
    std::cerr << "            -o directory     : output folder" << std::endl;
    std::cerr << "            -t directory     : temporary folder" << std::endl;
    std::cerr << "            -x 160           : scaled width of output image"    << std::endl;
    std::cerr << "            -y 120           : scaled height of output image"    << std::endl;
    std::cerr << "            -e               : exact frame grab, instead of duplicate frame" << std::endl;
    std::cerr << "            -s 500           : frame range, started at wanted frame (e.g 500 : 20s)" <<    std::endl;
    std::cerr << "            -i 25            : space beetween frames at selected range (resolution at PAL - 1/25s)" <<    std::endl;
    std::cerr << "            -c 5             : number of extracted frames of an recording or within selected range" << std::endl;
#ifdef DEBUG
    std::cerr << "            -g gobfile       : reread demuxed gobfile" <<    std::endl;
#endif
    std::cerr << std::endl << std::endl;
}

int main(int argc, char *argv[])
{
    int width = -1;
    int height = -1;
    bool exact = false;
    std::string szGOP, szFolder, szOutPath, szTempPath, s;


    if(-1 != option(argc, argv, 'x', true, s))
    {
        width =((atoi(s.c_str()) >> 1) << 1);    // Only /2
    }
    if(-1 != option(argc, argv, 'y', true, s))
    {
        height =((atoi(s.c_str()) >> 1) << 1);
    }
    if(-1 != option(argc, argv, 'e', false, s))
    {
        exact = true;
    }

    szOutPath = (".");
    option(argc, argv, 'o', true, szOutPath);
    szTempPath = szOutPath;
    option(argc, argv, 't', true, szTempPath);

    std::vector < int >nFrame;
    int n = 0;
    std::string f;
    
    while(-1 !=(n = option(argc, argv, 'f', true, f, n))) {
        int frame = atoi(f.c_str());
        if(frame < 0) {
            std::cerr << "ignore negative frame" << std::endl << std::endl;
        } else {
            nFrame.push_back(frame);
        }
    }

    if(!nFrame.empty()) {
        std::sort(nFrame.begin(), nFrame.end());
    }

    if(-1 == option(argc, argv, 'r', true, szFolder)) {
        std::cerr << "missing vdr recording folder" << std::endl << std::endl;
        help(argc, argv);
        return 1;
    }

    static const char* files[] = { "index.vdr", "index" };

    struct stat64 ds;
    std::string szIndex;
    int nIndexVersion = -1;
    for(unsigned int l = 0; l < 2; ++l) {
      std::stringstream ss;
      ss << szFolder;
      if('/' != *szFolder.rbegin())
          ss << '/';
      ss << files[l];
      ss << std::ends;
      szIndex = ss.str();

      if(!stat64(szIndex.c_str(), &ds)) {
          nIndexVersion = l;
          break;
      }
    }
    if(-1 == nIndexVersion) {
        std::cerr << "Can't find index file at " << szFolder << std::endl;
        return 1;
    }

    int nTotalFrames = (ds.st_size / 8);
    if(nTotalFrames <= 0) {
        std::cerr << "Empty index file : " << szIndex << std::endl;
        return 1;
    }

    if(-1 != option(argc, argv, 's', true, s)) {

        int range = atoi(s.c_str());
        if(range <= 0) {
            std::cerr << "none or negative frame range" << std::endl << std::endl;
            return 1;
        }

        int inter = 25;
        if(-1 != option(argc, argv, 'i', true, s)) {
            inter = atoi(s.c_str());
            if(inter <= 0) {
                std::cerr << "none or negative frame space" << std::endl << std::endl;
                return 1;
            }
        }


        if(-1 != option(argc, argv, 'c', true, s)) {
            int count = atoi(s.c_str());
            if(count <= 0) {
                std::cerr << "none or negative frame count" << std::endl << std::endl;
                return 1;
            }
            inter = range / count;
            if(inter<=0)
            {
                std::cerr << "count bigger then selected frame range, limit interval to 1" << std::endl << std::endl;
                inter = 1;
            }
        }

        int nLastFrame = 0;
        if(!nFrame.empty())
            nLastFrame = *nFrame.rbegin();

        int begin = nLastFrame;
        int end   = nLastFrame + range;

        if(end > nTotalFrames) {
            end = nTotalFrames;
            std::cerr << "wanted end frame from selected range, bigger then available frames. Limit end frame to " << end << std::endl << std::endl;
        }

        for(int i = begin; i < end; i += inter) {
            nFrame.push_back(i);
        }
    } else {
        if(-1 != option(argc, argv, 'c', true, s)) {
            int count = atoi(s.c_str());
            if(count <= 0) {
                std::cerr << "none or negative frame count" << std::endl << std::endl;
                return 1;
            }
            int nLastFrame = 0;
            if(!nFrame.empty())
                nLastFrame = *nFrame.rbegin();

            int begin = nLastFrame;
            int inter = (nTotalFrames - nLastFrame) / count;
            if(inter<=0)
            {
                std::cerr << "count bigger then frame selected range, limit interval to 1" << std::endl << std::endl;
                inter = 1;
            }

            for(int i = begin + (inter/2); i < nTotalFrames; i += inter) {
                nFrame.push_back(i);
            }
        }
    }

    if(nFrame.empty()) {
        std::cerr << "none frame defined, use first frame" << std::endl << std::endl;
        nFrame.push_back(0);
    }

#ifdef DEBUG
    std::cout << "Want Frames : ";
    std::vector < int >::const_iterator i = nFrame.begin();
    std::vector < int >::const_iterator e = nFrame.end();
    for(; i != e; ++i) {
        std::cout << (*i) << " ";
    }
    std::cout << std::endl;

    if(-1 != option(argc, argv, 'g', true, szGOP)) {
      std::vector < int >::const_iterator i = nFrame.begin();
      std::vector < int >::const_iterator e = nFrame.end();
      for(; i != e; ++i)
            if(!decodegop(szGOP,szOutPath,*i, width, height,exact));
            return 1;
        return 0;    // Success
    }
#endif //DEBUG
    std::vector < std::pair<tFrame,tFrame> > nGOP;
    if(ReadIndexFile(szIndex, nIndexVersion, nFrame, nGOP)) {
        if(ReadRecordings(szFolder, nIndexVersion, 
                          szOutPath, szTempPath, 
                          nGOP, width, height, exact, true)) {
            return 0;    // Success
            }
    }
    return 1;
}
