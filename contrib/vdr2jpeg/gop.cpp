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
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <time.h>
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <algorithm>
#include "ffm.h"
#include "gop.h"
#include "mpegdec.h"

bool operator >>(std::istream & i, tFrame & x)
{
    i.read((x.u.rawdata), sizeof(x.u.rawdata));    // Read all data in one step
    if(i.gcount() == sizeof(x.u.rawdata)) {
      return true;
    } else {
      return false;
    }
}

std::ostream & operator <<(std::ostream & o, const tFrame & x)
{
    o << " I-Frame = " << x.nIFrame;
//#ifdef DEBUG
//    o << " Offset = " << x.u.pes.offset;
//    o << " File = " <<(int) x.u.pes.number;
//    o << " Type = " <<(int) x.u.pes.type;
//    o << " Reserved : " << x.u.pes.reserved;
//#endif // DEBUG
    return o;
}


bool ReadIndexFile(const std::string & szFile, int nIndexVersion, 
                   const std::vector < int >&nFrames, 
                   std::vector < std::pair<tFrame,tFrame> > &nGOP)
{
    if(szFile.empty()) {
        std::cerr << "Missing index file" << std::endl;
        return false;
    }

    if(nFrames.empty()) {
        std::cerr << "Missing wanted frames" << std::endl;
        return false;
    }

    try
    {
        std::ifstream f(szFile.c_str(), std::ifstream::in | std::ifstream::binary);
        
        if(f.fail()) {
            std::cerr << "Can't open file : " << szFile << std::endl;
        return false;
        }
        std::vector < int >::const_iterator i = nFrames.begin();
        std::vector < int >::const_iterator e = nFrames.end();
        for(; i != e && f.good(); ++i) {
          std::pair<tFrame,tFrame> gop;
          tFrame x( *i );
          f.seekg(x.nIFrame * 8, std::ifstream::beg);
            do
            {
                if(!f.good())
                {
                    std::cerr << "Seek behind end of file : ";
                    std::cerr << szFile;
                    std::cerr << " at first frame ";
                    std::cerr << x.nIFrame << std::endl;
                    return false;
                }
                if(!(f >> x)) {
                    std::cerr << "Incomplete struct : ";
                    std::cerr << szFile;
                    std::cerr << " at first frame ";
                    std::cerr << x.nIFrame << std::endl;
                    return false;                  
                }
                if(!x.bIsIFrame(nIndexVersion))
                {
                    f.seekg(8 * 2 * -1, std::ifstream::cur);
                    if(x.nIFrame > 0)
                      --x.nIFrame;
                    else {
                      std::cerr << "Missing start struct : ";
                      std::cerr << szFile;
                      std::cerr << " at first frame ";
                      std::cerr << x.nIFrame << std::endl;
                      return false;
                    }
                }
            }
            while(!x.bIsIFrame(nIndexVersion)); // loop until found I-Frame

            gop.first = x;    //Remember I-Frame
            do
            {
                ++x.nIFrame;
                if(!f.good())
                {
                    std::cerr << "Seek behind end of file : ";
                    std::cerr << szFile;
                    std::cerr << " at second frame ";
                    std::cerr << x.nIFrame << std::endl;
                    return false;
                }
                if(!(f >> x)) {
#ifdef DEBUG
                    std::cerr << "Incomplete struct : ";
                    std::cerr << szFile;
                    std::cerr << " at Frame ";
                    std::cerr << x.nIFrame << std::endl;
#endif
                    return true;                  
                }
            }
            while(f.good() && !x.bIsIFrame(nIndexVersion));    // Build IBBP..I -> break on next I-Frame
            gop.second = x;
            nGOP.push_back(gop);    //Remember I-Frame
        }
        f.close();
        return true;
    }
    catch(...) {
        std::cerr << "Something fail at read " << szFile << std::endl;
        return false;
    }
}

bool ReadIndexFileFull(const std::string & szFile, int nIndexVersion, 
                       std::vector < std::pair<tFrame,tFrame> > &nGOP,
                       bool bIntraOnly,
                       unsigned int &nFirst, unsigned int nLimit)
{
    if(szFile.empty()) {
        std::cerr << "Missing index file" << std::endl;
        return false;
    }

    try
    {
        std::ifstream f(szFile.c_str(), std::ifstream::in | std::ifstream::binary);
        
        if(f.fail()) {
          std::cerr << "Can't open file : " << szFile << std::
              endl;
          return false;
        }

        std::pair<tFrame,tFrame> gop;
        tFrame x(nFirst);
        f.seekg(nFirst * 8, std::ifstream::beg);

        // Search first I-Frame
        while(bIntraOnly && f.good()) {
          if(!(f >> x)) {
              std::cerr <<
                  "Incomplete struct : ";
              std::cerr << szFile;
              std::cerr << " at Frame ";
              std::cerr << x.nIFrame << std::endl;
              return false;                  
          }
          if(x.bIsIFrame(nIndexVersion)) {
            break;
          }
          ++x.nFrame;
          ++x.nIFrame;
        }
        // Read all frames
        while(f.good()) {

          gop.first = x;    //First I-Frame

          do // Build IBBP..I -> break on next I-Frame
          {
            if(!(f >> x)) {
#ifdef DEBUG
                std::cerr <<
                    "Incomplete struct : ";
                std::cerr << szFile;
                std::cerr << " at Frame ";
                std::cerr << x.nIFrame << std::endl;
#endif
                return true;                  
            }
            ++x.nFrame;
            ++x.nIFrame;
            if(!bIntraOnly || x.bIsIFrame(nIndexVersion)) {
              break;
            }
          } while(f.good());    

          gop.second = x; //Last I-Frame

//        std::cerr << x << std::endl;
          nGOP.push_back(gop);    //Remember GOP IBBP..I
          if(x.nFrame >= (nFirst + nLimit)) {
            nFirst = x.nFrame;
            break;
          }
        }
        f.close();
        return true;
    }
    catch(...) {
        std::cerr << "Something fail at read " << szFile << std::endl;
        return false;
    }
}

int copy(const char * inn, const char * outn )  
{  
    char buffer[8192];
    int count,readed = 0,written = 0;  
    int in,out;  

    in = open(inn,O_RDONLY);  
    if(in == -1)
        return -1;
    out = open(outn,O_CREAT|O_TRUNC|O_WRONLY,S_IRUSR|S_IWUSR|S_IRGRP|S_IROTH);  
    if(out == -1)
        return -1;

    while(0 < (count = read(in,buffer,sizeof(buffer)))) {
        readed += count;
        written += write(out,buffer,count);
        if(readed != written)
            break;
    }
    return ((readed == written) ? 0 : -1);
} 

bool temppath(const std::string & szOutPath, std::string & szTmpBase )  
{
    unsigned int nT = time(0);
    srand(nT);

    std::stringstream so;
    so << szOutPath;
    if('/' != *szOutPath.rbegin())
        so << '/';
    so << "tmp-vdr2jpeg-";
    so.fill('0');
    so.width(8);
    so << std::hex;
    so << rand();
    szTmpBase = so.str();
    return true;
}

void unlinkTmpfiles(const std::string & szTmpBase, bool bJPEG )
{
    std::stringstream so;
    struct stat64 ds;
    for(unsigned int i = 1 ; i <= 99 ; ++i)
    {
        so.str("");
        so << szTmpBase;
        so.fill('0');
        so.width(2);
        so << i;
        so << (bJPEG ? ".jpg" : ".ppm");
        so << std::ends;
        std::string szTmp(so.str());

        if(stat64(szTmp.c_str(), &ds)) {
            break;
        }
        if(-1 == unlink(szTmp.c_str())) {
            perror(szTmp.c_str());
            break;
        }
    }
    so.str("");
    so << szTmpBase;
    so << ".mpv";
    so << std::ends;
    std::string szTmpMVP(so.str());
    if(stat64(szTmpMVP.c_str(), &ds)) {
        return;
    }
    if(-1 == unlink(szTmpMVP.c_str())) {
        perror(szTmpMVP.c_str());
        return;
    }
}

bool linkTmpfile(const std::string & szTmp, const std::string & szOutPath,
                 int nFrame, bool bJPEG)
{
    struct stat64 ds;
    std::stringstream so;

    so << szOutPath;
    if('/' != *szOutPath.rbegin())
        so << '/';
    so.fill('0');
    so.width(8);
    so << nFrame;
    so << (bJPEG ? ".jpg" : ".ppm");
    so << std::ends;
    std::string szFile(so.str());


    if(!stat64(szFile.c_str(), &ds)) {
        if(-1 == unlink(szFile.c_str())) {
            perror(szFile.c_str());
            return false;
        }
    }

    int nErr = link(szTmp.c_str(),szFile.c_str());
    if(-1 == nErr && (errno == EXDEV || errno == EPERM ))
    {
        nErr = copy(szTmp.c_str(),szFile.c_str());
    }
    if(0 != nErr || 0 != chmod(szFile.c_str(),S_IRUSR|S_IWUSR|S_IRGRP|S_IROTH) )
    {
       if(errno == EEXIST || errno == EACCES)
           perror(szFile.c_str());
       else
           perror(szTmp.c_str());
       return false;
    }
    return true;
}

bool handleTmpfile(const std::string & szTmpBase, const std::string & szOutPath,
                 int nFrame, int nFrameBase, bool exact, bool bJPEG, bool bLink,
                 unsigned int nWidth,unsigned int nHeight)
{
    struct stat64 ds;

    std::string szTmp;
    std::stringstream so;
    // started from wantet frame, avoid skipped duplicated frames
    // look backward
    for(unsigned int n = (nFrame - nFrameBase + 1) ; n > 0 ; --n)
    {
        so.str("");
        so << szTmpBase;
        so.fill('0');
        so.width(2);
        so << n;
        so << (bJPEG ? ".jpg" : ".ppm");
        so << std::ends;
        std::string szTmpTry = so.str();

        if(stat64(szTmpTry.c_str(), &ds)) {
            if(exact) {
                std::cerr << "Can't find tmp file : " << szTmpTry.c_str() << std::endl;
                return false;
            }
        }
        else 
        {
            szTmp = szTmpTry;
            break;
        }
    }

    if(szTmp.length() == 0)
    {    
        // look forward backward
        for(unsigned int n = (nFrame - nFrameBase + 1) ; n <= 99 ; ++n)
        {
            so.str("");
            so << szTmpBase;
            so.fill('0');
            so.width(2);
            so << n;
            so << (bJPEG ? ".jpg" : ".ppm");
            so << std::ends;
            std::string szTmpTry = so.str();

            if(stat64(szTmpTry.c_str(), &ds)) {
                if(exact) {
                    std::cerr << "Can't find tmp file : " << szTmpTry.c_str() << std::endl;
                    return false;
                }
            }
            else 
            {
                szTmp = szTmpTry;
                break;
            }
        }
    }
    if(szTmp.length() == 0)
    {
        std::cerr << "Can't find any tmp file" << std::endl;
        return false;
    }       
    if(bLink) {
      return linkTmpfile(szTmp,szOutPath, nFrame, bJPEG );
    } 
    return false;
}


bool ReadGOP(const std::string & szFile, off_t nBegin, off_t nLength, char *pMem )
{
    std::ifstream f(szFile.c_str(),
              std::ifstream::in | std::ifstream::binary);
    if(f.fail()) {
        std::cerr << "Can't open file : " << szFile << std::endl;
        return false;
    }

    if(nBegin < 0) {
        std::cerr << "Negativ seek at file : " << szFile << std::endl;
        return false;
    }

    if(nLength < 0) {
        std::cerr << "Negativ length at file : " << szFile << std::endl;
        return false;
    }

    if(nBegin != 0) {
      f.seekg(nBegin, std::ifstream::beg);    // Seek to I-Frame
    }
#ifdef DEBUG
    std::cerr << "Seek file : " << szFile << " to "<< nBegin << std::endl;
#endif

    f.read(pMem, nLength);
    if (f.gcount() != nLength) {
        std::cerr << "Can't read all from file : " << szFile << std::endl;
        return false;
    }
#ifdef DEBUG
    std::cerr << "Read file : " << szFile << " length "<< nLength << std::endl;
#endif
    return true;
}

bool ReadRecordings(const std::string & szFolder, int nIndexVersion, 
        const std::string & szOutPath, const std::string & szTempPath,
        const std::vector < std::pair<tFrame,tFrame> > &nGOP, int width, int height,
        bool exact, bool bJPEG)
{
    if(szFolder.empty())
    {
        std::cerr << "Missing VDR-recording folder" << std::endl;
        return false;
    }

    if(nGOP.empty())
    {
        std::cerr << "Missing wanted GOP" << std::endl;
        return false;
    }

    unsigned int nError = 0;
    std::vector < std::pair<tFrame,tFrame> >::const_iterator i = nGOP.begin();
    std::vector < std::pair<tFrame,tFrame> >::const_iterator e = nGOP.end();

    for(; i != e; ++i)
    {
#ifdef DEBUG
        std::cout << "Extract GOP : ";
        std::cout << i->first << " / " << i->second << std::endl;
#endif //DEBUG

        //Skip empty frames (most at end)
        if(i->first.GetOffset(nIndexVersion) == i->second.GetOffset(nIndexVersion)) {
          continue;
        }

        std::stringstream ss;
        std::string szTmpBase;
        if(!temppath(szTempPath,szTmpBase))
        {
            std::cerr << "Can't get tempname" << std::endl;
            return false;
        }

        ss << szTmpBase;
        ss << ".mpv";
        ss << std::ends;
        std::string szTmpMVP(ss.str());

        try
        {
            char *pMem = NULL;
            off_t nSize  = 0;

            // Offset bigger then current 00x.vdr files, goto next
            if((i->first.GetOffset(nIndexVersion) >= i->second.GetOffset(nIndexVersion) 
             || i->first.GetFileNr(nIndexVersion) != i->second.GetFileNr(nIndexVersion)) 
             && i->second.GetOffset(nIndexVersion) != 0) {

                ss.str("");
                ss << szFolder;
                if('/' != *szFolder.rbegin())
                    ss << '/';
                i->first.buildFilename(ss,nIndexVersion); // Filenumber 001.vdr ...
                ss << std::ends;
                std::string szFile(ss.str());

                struct stat64 ds;
                if(stat64(szFile.c_str(), &ds)) {
                    std::cerr << "Can't find file : " << szFile << std::endl;
                    std::cerr << i->first  << " / " << i->second << std::endl;
                    return false;
                }

                if(i->first.GetOffset(nIndexVersion) >= (ds.st_size)) {
                    std::cerr << "Offset bigger than current file : " << szFile << std::endl;
                    std::cerr << i->first  << " / " << i->second << std::endl;
                    return false;
                }

                nSize = ds.st_size - i->first.GetOffset(nIndexVersion) + i->second.GetOffset(nIndexVersion);
                if(nSize <= 0
                    || nSize >=(1 << 24)
                    || NULL ==(pMem = new char[nSize])) {
                    std::cerr << "Can't alloc memory for file : " << szFile << std::endl;
                    std::cerr << "want :" << nSize << " bytes" << std::endl;
                    std::cerr << i->first  << " / " << i->second << std::endl;
                    return false;
                }

                if(!ReadGOP(szFile, i->first.GetOffset(nIndexVersion), ds.st_size - i->first.GetOffset(nIndexVersion), pMem)) {
                  delete[]pMem;
                  return false;
                }

                ss.str("");
                ss << szFolder;
                if('/' != *szFolder.rbegin())
                    ss << '/';
                i->second.buildFilename(ss,nIndexVersion); // Filenumber 002.vdr ...
                ss << std::ends;
                szFile = ss.str();

                if(stat64(szFile.c_str(), &ds)) {
                    std::cerr << "Can't find file : " << szFile << std::endl;
                    std::cerr << i->first  << " / " << i->second << std::endl;
                    return false;
                }

                if(i->second.GetOffset(nIndexVersion) >=(ds.st_size)) {
                    std::cerr << "Offset bigger than current file : " << szFile << std::endl;
                    std::cerr << i->first  << " / " << i->second << std::endl;
                    return false;
                }

                if(!ReadGOP(szFile, 0, i->second.GetOffset(nIndexVersion), pMem + i->first.GetOffset(nIndexVersion))) {
                  delete[]pMem;
                  return false;
                }

            } else {

                ss.str("");
                ss << szFolder;
                if('/' != *szFolder.rbegin())
                    ss << '/';
                i->first.buildFilename(ss,nIndexVersion); // Filenumber 001.vdr ...
                ss << std::ends;
                std::string szFile(ss.str());

                struct stat64 ds;
                if(stat64(szFile.c_str(), &ds))
                {
                    std::cerr << "Can't find file : " << szFile << std::endl;
                    std::cerr << i->first  << " / " << i->second << std::endl;
                    return false;
                }
                if(i->first.GetOffset(nIndexVersion) >=(ds.st_size)) {
                    std::cerr << "Offset bigger than current file : " << szFile << std::endl;
                    std::cerr << i->first  << " / " << i->second << std::endl;
                    return false;
                }

                // size of GOP
                nSize = i->second.GetOffset(nIndexVersion) 
                      ? i->second.GetOffset(nIndexVersion) - i->first.GetOffset(nIndexVersion)
                      : ds.st_size - i->first.GetOffset(nIndexVersion);
                if(nSize <= 0
                    || nSize >=(1 << 24)
                    || NULL ==(pMem = new char[nSize]))
                {
                    std::cerr << "Can't alloc memory for file : " << szFile << std::endl;
                    std::cerr << "want :" << nSize << " bytes" << std::endl;
                    std::cerr << i->first  << " / " << i->second << std::endl;
                    return false;
                }

                if(!ReadGOP(szFile, i->first.GetOffset(nIndexVersion), nSize, pMem)) {
                  delete[]pMem;
                  return false;
                }
            }


/* 
00 00 01 // PES Startcode
e4       // Streamtype
07 fa    // Length => 2042
84 c0    // notused
0b       // header_length
*/
            int nMagicFormat = -1;
            static const unsigned char pesMagic[3] = { 0x00, 0x00, 0x01 };
            static const unsigned char tsMagic[3] = { 0x47, 0x40, 0x00 };
            if(0 == memcmp(pMem, pesMagic, sizeof(pesMagic))) {
              nMagicFormat = 1;
            } else if(0 == memcmp(pMem, tsMagic, sizeof(tsMagic))) {
              nMagicFormat = 2;
            } else {
                std::cerr << "No valid magic found, at current pes packet, for file : " << szFolder << std::endl;
                std::cerr << i->first  << " / " << i->second << std::endl;
#ifdef DEBUG
#if 0
                for(unsigned int b = 0; b < nSize; ++b) {        
                  if(0 == b % 16) {
                     std::cerr << std::endl;
                     std::cerr.fill('0');
                     std::cerr.width(4);
                     std::cerr << std::hex << b;
                     std::cerr << " ";
                  }
#else
                std::cerr << "magic and streamcode are : ";
                for(unsigned int b = 0; b < 4 && b < nSize; ++b) {   
#endif
                  std::cerr.fill('0');
                  std::cerr.width(2);
                  std::cerr << std::hex << (unsigned int)(*(pMem + b) & 0xFF);
                  std::cerr << " ";
                }
                std::cerr << std::endl;
#endif
                delete[]pMem;
                return false;
            }

            bool bRet = false;
            if(nMagicFormat == 1) {
              demux_reset();
              bRet = 0 == demuxPES ((uint8_t*)pMem,(uint8_t*)pMem + nSize, szTmpMVP.c_str(), 0);
            } else {
              demux_reset();
              bRet = 0 == demuxTS ((uint8_t*)pMem,(uint8_t*)pMem + nSize, szTmpMVP.c_str(), 0);
            }
            if(bRet)
            {
              std::stringstream so;
              so << szTmpBase;
              so << "%2d";
              so << (bJPEG ? ".jpg" : ".ppm");
              so << std::ends;
              std::string szTmpMask(so.str());
              bRet = decode(szTmpMVP.c_str(), szTmpMask.c_str(), width, height);
              if(bRet) 
              {
                  if(!handleTmpfile(szTmpBase, szOutPath,i->first.nFrame,
                                    i->first.nIFrame, exact, bJPEG, bJPEG,width, height)) {
                    std::cerr << "Can't handle file : " << szFolder << std::endl;
                    std::cerr << i->first  << " / " << i->second << std::endl;
                    return false;
                  }

                  // look for more picture from same GOP
                  std::vector < std::pair<tFrame,tFrame> >::const_iterator j = i + 1;
                  std::vector < std::pair<tFrame,tFrame> >::const_iterator e = nGOP.end();
                  for(;j != e; ++j ,++i) 
                  {
                      if((i->first.nIFrame != j->first.nIFrame ) 
                        ||(!handleTmpfile(szTmpBase, szOutPath,i->first.nFrame, 
                                          i->first.nIFrame, exact, bJPEG, bJPEG, width, height)))
                          break;
                  }
              }
            }
            unlinkTmpfiles(szTmpBase, bJPEG);

            delete[]pMem;
            if(!bRet)
            {
                std::cerr << "decode failed, for file : " << szFolder << std::endl;
                std::cerr << i->first  << " / " << i->second << std::endl;
                nError += 1;
            }
        }
        catch(...)
        {
            std::cerr << "Something fail at read " << szFolder << std::endl;
            return false;
        }
    }
    return (nError == 0);
}

bool decodegop(const std::string & szFile,
               const std::string & szOutPath,
               int nFrame, int width, int height,
               bool exact, bool bJPEG)
{
    struct stat64 ds;
    if(stat64(szFile.c_str(), &ds)) {
        std::cerr << "Can't stat file : " << szFile << std::endl;
        return false;
    }
    try
    {
        std::string szTmpBase;
        if(!temppath(szOutPath, szTmpBase))
        {
            std::cerr << "Can't get tempname" << std::endl;
            return false;
        }

        std::stringstream so;
        so << szTmpBase;
        so << "%2d";
        so << (bJPEG ? ".jpg" : ".ppm");
        so << std::ends;
        std::string szTmpMask(so.str());

        bool bRet = decode(szFile.c_str(), szTmpMask.c_str(), width, height)
                    && handleTmpfile(szTmpBase, szOutPath, exact ? nFrame : 0 , 0, exact, bJPEG, true, width, height );

        unlinkTmpfiles(szTmpBase, bJPEG);

        return bRet;

    }
    catch(...)
    {
        std::cerr << "Something fail at read " << szFile << std::endl;
    }
    return false;
}

