/*
 * Simple program to grab images from VDR Recording
 *
 * Copyright(c) 2005-2007 Andreas Brachold
 * 
 * demux ported from vdrsync.pl : Copyright(c) 2005 Peter Sebbel 
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

#include <sys/types.h>
#include <sys/stat.h>       
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <time.h>
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <algorithm>
#include "ffm.h"


static const char *VERSION        = "0.0.12";

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

std::istream & operator >>(std::istream & i, tFrame & x)
{
    i.read((x.u.rawdata), sizeof(x.u.rawdata));    // Read all data in one step
    return i;
}

#ifdef DEBUG
std::ostream & operator <<(std::ostream & o, const tFrame & x)
{
    o << "Frame = " << x.nFrame;
    o << " I-Frame = " << x.nIFrame;
/*
    o << " Offset = " << x.u.f.offset;
    o << " Type = " <<(int) x.u.f.type;
    o << " Number = " <<(int) x.u.f.number;
    o << " Reserved : " << x.u.f.reserved;
*/
    return o;
}
#endif // DEBUG


bool ReadIndexFile(const std::string & szFolder, std::vector < int >&nFrames, std::vector < std::pair<tFrame,tFrame> > &nGOP)
{
    if(szFolder.empty()) {
        std::cerr << "Missing VDR-recording folder" << std::endl;
        return false;
    }

    if(nFrames.empty()) {
        std::cerr << "Missing wanted frames" << std::endl;
        return false;
    }

    std::stringstream ss;
    ss << szFolder;
    if('/' != *szFolder.rbegin())
        ss << '/';
    ss << "index.vdr";
    ss << std::ends;
    std::string szFile(ss.str());
    try
    {
        std::ifstream f(szFile.c_str(), std::ifstream::in | std::ifstream::binary);
            if(f.fail()) {
        std::cerr << "Can't open file : " << szFile << std::
            endl;
        return false;
    }
    std::vector < int >::const_iterator i = nFrames.begin();
    std::vector < int >::const_iterator e = nFrames.end();
    for(; i != e && f.good(); ++i) {
    std::pair<tFrame,tFrame> gop;
    tFrame x( (*i) );
    f.seekg(x.nIFrame * 8, std::ifstream::beg);
            do
            {
                if(!f.good())
                {
                    std::cerr <<
                        "Seek behind end of file : ";
                    std::cerr << szFile;
                    std::cerr << " at Frame ";
                    std::cerr << x.nIFrame << std::endl;
                    return false;
                }
                f >> x;
                if(x.u.f.type != 1)
                {
                    f.seekg(8 * 2 * -1, std::ifstream::cur);
                      --x.nIFrame;
                }
            }
            while(x.u.f.type != 1);    // found I-Frame

            gop.first = x;    //Remember I-Frame

            do
            {
                ++x.nIFrame;
                if(!f.good())
                {
                    std::cerr <<
                        "Seek behind end of file : ";
                    std::cerr << szFile;
                    std::cerr << " at Frame ";
                    std::cerr << x.nIFrame << std::endl;
                    return false;
                }
                f >> x;
            }
            while(f.good() && x.u.f.type != 1);    // Build IBBP..I -> break on next I-Frame
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

void unlinkTmpfiles(const std::string & szTmpBase )
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
        so << ".jpg";
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

bool copyTmpfile(const std::string & szTmpBase, const std::string & szOutPath,int nFrame, int nFrameBase, bool exact )
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
        so << ".jpg";
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
            so << ".jpg";
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

    so.str("");
    so << szOutPath;
    if('/' != *szOutPath.rbegin())
        so << '/';
    so.fill('0');
    so.width(8);
    so << nFrame;
    so << ".jpg";
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




bool ReadRecordings(const std::string & szFolder, const std::string & szOutPath,
        const std::vector < std::pair<tFrame,tFrame> > &nGOP, int width, int height,
        bool exact)
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

    std::vector < std::pair<tFrame,tFrame> >::const_iterator i = nGOP.begin();
    std::vector < std::pair<tFrame,tFrame> >::const_iterator e = nGOP.end();

    int nOffset = 0;
    for(; i != e; ++i)
    {
#ifdef DEBUG
        std::cout << "Extract GOP : ";
           std::cout << (const tFrame&)(i->first) << " / " << (const tFrame&)(i->second) << std::endl;
#endif //DEBUG

        std::stringstream ss;
        ss << szFolder;
        if('/' != *szFolder.rbegin())
            ss << '/';
        ss.fill('0');
        ss.width(3);
        ss << (int)i->first.u.f.number; // Filenumber 001.vdr ...
        ss << ".vdr";
        ss << std::ends;
        std::string szFile(ss.str());


        std::string szTmpBase;
        if(!temppath(szOutPath,szTmpBase))
        {
            std::cerr << "Can't get tempname" << std::endl;
            return false;
        }

        ss.str("");
        ss << szTmpBase;
        ss << ".mpv";
        ss << std::ends;
        std::string szTmpMVP(ss.str());

        try
        {
            struct stat64 ds;
            if(stat64(szFile.c_str(), &ds))
            {
                std::cerr << "Can't find file : " << szFile << std::endl;
                return false;
            }
            // Offset bigger then current 00x.vdr files, goto next
            if(i->first.u.f.offset >=(ds.st_size))
            {
                std::cerr <<
                    "Offset bigger than current file : "
                    << szFile << std::endl;
                return false;
            }

            std::ifstream f(szFile.c_str(),
                     std::ifstream::in | std::ifstream::
                     binary);
                        if(f.fail())
            {
                std::cerr << "Can't open file : " << szFile << std::endl;
                return false;
            }
            int nStart = i->first.u.f.offset;
            f.seekg(nStart - nOffset, std::ifstream::beg);    // Seek to I-Frame

            // size of GOP
            int nSize =i->second.u.f.offset - nStart;
            char *pMem = NULL;
            if(nSize <= 0
                || nSize >=(1 << 24)
                || NULL ==(pMem = new char[nSize]))
            {
                std::cerr << "Can't alloc memory for file : "
                    << szFile << std::endl;
                std::cerr << "want :" << nSize << " bytes" <<
                    std::endl;
                return false;
            }
            f.read(pMem, nSize);
            if (f.gcount() != nSize)
            {
                std::cerr << "Can't read all from file : " << szFile << std::endl;
                delete[]pMem;
                return false;
            }

/* 
00 00 01 // Startcode
e4       // Streamtype
07 fa    // Length => 2042
84 c0    // notused
0b       // header_length
*/
            static const unsigned char packetMagic[3] = { 0x00, 0x00, 0x01 };
            if(0 != memcmp(pMem, packetMagic, 3))
            {
                std::cerr <<
                    "No valid magic found, at current packet, for file : "
                    << szFile << std::endl;
                std::cerr.fill('0');
                std::cerr.width(2);
                std::cerr << "found : 0x" << std::
                    hex <<(unsigned int)(*(pMem + 0) &
                                   0xFF) << std::
                    hex <<(unsigned int)(*(pMem + 1) &
                                   0xFF) << std::
                    hex <<(unsigned int)(*(pMem + 2) &
                                   0xFF) <<
                    " streamcode : 0x";
                std::cerr.fill('0');
                std::cerr.width(2);
                std::cerr <<(unsigned int)(*(pMem + 3)) <<
                    std::endl;
                delete[]pMem;
                return false;
            }
            int nOffset = 0;
            int nPackets = 0;


            std::ofstream fo;

            while(nOffset < nSize)
            {
                int pLength =(((unsigned char) *(pMem + nOffset + 4)) << 8) +
                             (((unsigned char) *(pMem + nOffset + 5)) << 0);
                int hLength =(((unsigned char) *(pMem + nOffset + 8)) << 0);
                unsigned char cStream =(unsigned char) *(pMem + nOffset + 3);
                if((cStream & 0xe0) == 0xe0)
                {    // Check for Stream 0xE0-0xEF
                    // Store payload
                    // |Header|......PaketLength| 
                    unsigned char *pBuffer =(unsigned char *) pMem + nOffset + 9 + hLength;
                    unsigned int nWrite =(pLength + 6) -(9 + hLength);

                    if(!fo.is_open()) // Open on first write.
                    {
                        fo.open(szTmpMVP.c_str(), std::ofstream::out | std::ofstream::binary);
                        if(!fo.good())
                            break;
                    }
                    fo.write((char *) pBuffer, nWrite);
                    if(!fo.good())
                        break;

                    ++nPackets;
                }
                nOffset +=(pLength + 6);


                if(nOffset <= 0)    // avoid negativ seek
                    break;
            }
            if(nPackets == 0 && nOffset >= nSize)
            {
                std::cerr << "No valid packet found, for file : " << szFile << std::endl;
                delete[]pMem;
                return false;
            }

            std::stringstream so;
            so << szTmpBase;
            so << "%2d";
            so << ".jpg";
            so << std::ends;
            std::string szTmpMask(so.str());

            bool bRet = decode(szTmpMVP.c_str(), szTmpMask.c_str(), width, height);
            if(bRet) 
            {
                copyTmpfile(szTmpBase, szOutPath,i->first.nFrame, i->first.nIFrame, exact );

                // look for more picture from same GOP
                std::vector < std::pair<tFrame,tFrame> >::const_iterator j = i + 1;
                std::vector < std::pair<tFrame,tFrame> >::const_iterator e = nGOP.end();
                for(;j != e; ++j ,++i) 
                {
                    if(i->first.nIFrame != j->first.nIFrame 
                        || !copyTmpfile(szTmpBase, szOutPath,j->first.nFrame, j->first.nIFrame, exact ))
                        break;
                }
            }

            unlinkTmpfiles(szTmpBase);

            delete[]pMem;
            if(!bRet)
            {
                std::cerr << "decode failed, for file : " << szFile << std::endl;
                return false;
            }
        }
        catch(...)
        {
            std::cerr << "Something fail at read " << szFile << std::endl;
            return false;
        }
    }
    return true;
}

bool decodegop(const std::string & szFile,
               const std::string & szOutPath,
               int nFrame, int width, int height,
               bool exact)
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
        so << ".jpg";
        so << std::ends;
        std::string szTmpMask(so.str());

        bool bRet = decode(szFile.c_str(), szTmpMask.c_str(), width, height)
                    && copyTmpfile(szTmpBase, szOutPath, exact ? nFrame : 0 , 0, exact );

        unlinkTmpfiles(szTmpBase);

        return bRet;
    }
    catch(...)
    {
        std::cerr << "Something fail at read " << szFile << std::endl;
        return -1;
    }
}

void help(int argc, char *argv[])
{
    std::cerr << "Usage: " << argv[0] << " (" << VERSION << ")" << std::endl;
    std::cerr << "            -r recordings    : VDR recording folder" <<    std::endl;
    std::cerr << "            -f frame         : wanted frame (resolution at PAL - 1/25s)" <<    std::endl;
    std::cerr << "            -o outdirectory  : output folder" << std::endl;
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

int option(int argc, char *argv[], const char opt, bool bParam,
    std::string & param, int n = 1)
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

// Helperclass for proper init/deinit ffmpeg
struct ffminit
{
    ffminit() { ffm_initalize();   }
   ~ffminit() { ffm_deinitalize();   }
};


int main(int argc, char *argv[])
{
    int width = -1;
    int height = -1;
    bool exact = false;
    std::string szGOP, szFolder, szOutPath("."), s;


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
    option(argc, argv, 'o', true, szOutPath);


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

    std::stringstream ss;
    ss << szFolder;
    if('/' != *szFolder.rbegin())
        ss << '/';
    ss << "index.vdr";
    ss << std::ends;
    std::string szIndex(ss.str());

    struct stat64 ds;
    if(stat64(szIndex.c_str(), &ds)) {
        std::cerr << "Can't access file : " << szIndex << std::endl;
        return 1;
    }
    int nTotalFrames = (ds.st_size / 8);
    if(nTotalFrames <= 0) {
        std::cerr << "Empty file : " << szIndex << std::endl;
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
      ffminit x;
      std::vector < int >::const_iterator i = nFrame.begin();
      std::vector < int >::const_iterator e = nFrame.end();
      for(; i != e; ++i)
            if(!decodegop(szGOP,szOutPath,*i, width, height,exact));
            return 1;
        return 0;    // Success
    }
#endif //DEBUG

    std::vector < std::pair<tFrame,tFrame> > nGOP;
    if(ReadIndexFile(szFolder, nFrame, nGOP)) {
        ffminit x;

        if(ReadRecordings(szFolder, szOutPath, nGOP, width, height,exact))
            return 0;    // Success
    }
    return 1;
}
