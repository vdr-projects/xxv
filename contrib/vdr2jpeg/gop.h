/*
 * Simple program to grab images from VDR Recording
 *
 * Copyright(c) 2005-2008 Andreas Brachold
 * 
 * demux ported from vdrsync.pl : Copyright(c) 2005 Peter Sebbel 
 *
 * This code is distributed under the terms and conditions of the
 * GNU GENERAL PUBLIC LICENSE. See the file COPYING for details.
 *
 */

#include <iostream>
#include <fstream>
#include <vector>

struct tFrame
{
    unsigned int nFrame;
    unsigned int nIFrame;
    union uIndex
    {
        struct tIndex
        {
            int32_t offset;
            unsigned char type;
            unsigned char number;
            int16_t reserved;
        } f;
        char rawdata[8];
    } u;
    tFrame()
    {
    };
    tFrame(int n)
    {
        nFrame = nIFrame = n;
    }
};

bool operator >> (std::istream & i, tFrame & x);
std::ostream & operator <<(std::ostream & o, const tFrame & x);


bool ReadIndexFile(const std::string & szFolder, std::vector < int >&nFrames, 
      std::vector < std::pair<tFrame,tFrame> > &nGOP);

bool ReadIndexFileFull(const std::string & szFolder, 
                       std::vector < std::pair<tFrame,tFrame> > &nGOP,
                       bool bIntraOnly,
                       unsigned int &nFirst, unsigned int nLimit);

int copy(const char * inn, const char * outn );

bool temppath(const std::string & szOutPath, std::string & szTmpBase );

void unlinkTmpfiles(const std::string & szTmpBase, bool bJPEG );

bool handleTmpfile(const std::string & szTmpBase, const std::string & szOutPath,
        int nFrame, int nFrameBase, bool exact, bool bJPEG, bool bLink,
                  unsigned int nWidth,unsigned int nHeight);

bool ReadRecordings(const std::string & szFolder, 
        const std::string & szOutPath, const std::string & szTempPath,
        const std::vector < std::pair<tFrame,tFrame> > &nGOP, int width, int height,
        bool exact, bool bJPEG = true);

bool decodegop(const std::string & szFile,
               const std::string & szOutPath,
               int nFrame, int width, int height,
               bool exact, bool bJPEG = true);

