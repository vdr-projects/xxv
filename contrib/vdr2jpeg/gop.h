/*
 * Simple program to grab images from VDR Recording
 *
 * Copyright(c) 2005-2010 Andreas Brachold
 * 
 * pes demux ported from vdrsync.pl : Copyright(c) 2005 Peter Sebbel 
 *
 * This code is distributed under the terms and conditions of the
 * GNU GENERAL PUBLIC LICENSE. See the file COPYING for details.
 *
 */

#include <iostream>
#include <fstream>
#include <vector>
#include <stdint.h>

struct tFrame
{
    unsigned int nFrame;
    unsigned int nIFrame;
    union uIndex
    {
        struct tIndexPES {
            int32_t offset;
            unsigned char type;
            unsigned char number;
            int16_t reserved;
        } pes;
        struct tIndexTS {
            uint64_t offset:40; // up to 1TB per file (not using off_t here - must definitely be exactly 64 bit!)
            int reserved:7;     // reserved for future use
            int independent:1;  // marks frames that can be displayed by themselves (for trick modes)
            uint16_t number:16; // up to 64K files per recording
        } ts;
        char rawdata[8];
    } u;
    tFrame()
    {
    };
    tFrame(int n)
    {
        nFrame = n;
        nIFrame = n - 6;
        if(n <= 6)
            nIFrame = 0;
    };
    bool bIsIFrame(int nVersion) const {
       if(nVersion == 0) {
          return u.pes.type == 1;
       } else {
          return u.ts.independent != 0;
       }
    };
    off_t GetOffset(int nVersion) const {
       if(nVersion == 0) {
          return u.pes.offset;
       } else {
          return u.ts.offset;
       }
    };
    unsigned int GetFileNr(int nVersion) const {
       if(nVersion == 0) {
          return u.pes.number;
       } else {
          return u.ts.number;
       }
    };
    void buildFilename(std::ostream & o, int nVersion) const {
      o.fill('0');
      o.width(nVersion == 0 ? 3 : 5);
      o << GetFileNr(nVersion); // Filenumber 002.vdr ...
      if(nVersion == 0)
        o << ".vdr";
      else
        o << ".ts";
    };
};

bool operator >> (std::istream & i, tFrame & x);
std::ostream & operator <<(std::ostream & o, const tFrame & x);


bool ReadIndexFile(const std::string & szFile, int nIndexVersion, 
      const std::vector < int >&nFrames, std::vector < std::pair<tFrame,tFrame> > &nGOP);

bool ReadIndexFileFull(const std::string & szFile, int nIndexVersion, 
                       std::vector < std::pair<tFrame,tFrame> > &nGOP,
                       bool bIntraOnly,
                       unsigned int &nFirst, unsigned int nLimit);

int copy(const char * inn, const char * outn );

bool temppath(const std::string & szOutPath, std::string & szTmpBase );

void unlinkTmpfiles(const std::string & szTmpBase, bool bJPEG );

bool handleTmpfile(const std::string & szTmpBase, const std::string & szOutPath,
        int nFrame, int nFrameBase, bool exact, bool bJPEG, bool bLink,
                  unsigned int nWidth,unsigned int nHeight);

bool ReadRecordings(const std::string & szFolder, int nIndexVersion, 
        const std::string & szOutPath, const std::string & szTempPath,
        const std::vector < std::pair<tFrame,tFrame> > &nGOP, int width, int height,
        bool exact, bool bJPEG = true);

bool decodegop(const std::string & szFile,
               const std::string & szOutPath,
               int nFrame, int width, int height,
               bool exact, bool bJPEG = true);

