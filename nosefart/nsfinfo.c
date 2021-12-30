/* nsfinfo : get/set nsf file info.
 *
 * by benjamin gerard <ben@sashipa.com> 2003/04/18
 *
 * This program supports nsf playing time calculation extension.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of version 2 of the GNU Library General 
 * Public License as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, 
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU 
 * Library General Public License for more details.  To obtain a 
 * copy of the GNU Library General Public License, write to the Free 
 * Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * Any permitted reproduction of these routines, in whole or in part,
 * must bear this legend.
 */

/*
	This file has been modified by Matthew Strait so that it can be
	used to do playing time calculation without using ben's idea of
	changing the NSF file format.  He wrote this as a stand-alone
	program.  I have modified it so that the parts I want are called
	from nosefart.  I also modified the calculation algorithm 
	somewhat.
	
	For this to work, the changes he made to other files in this source
	tree have been left alone.  Therefore, there may be references to 
	the "NSF2" file format in the code, even though this version of
	nosefart does not use it.
*/

#include "nes6502.h"
#include "types.h"
#include "nsf.h"
#include "config.h"

static int quiet = 0;

#ifdef NSF_PLAYER
#define  NES6502_4KBANKS
#endif

#ifdef NES6502_4KBANKS
#define  NES6502_NUMBANKS  16
#define  NES6502_BANKSHIFT 12
#else
#define  NES6502_NUMBANKS  8
#define  NES6502_BANKSHIFT 13
#endif

extern uint8 *acc_nes6502_banks[NES6502_NUMBANKS];
extern int max_access[NES6502_NUMBANKS];

static void msg(const char *fmt, ...)
{
    return;
}

static void lpoke(uint8 *p, int v)
{
  p[0] = v;
  p[1] = v >> 8;
  p[2] = v >> 16;
  p[3] = v >> 24;
}

static int nsf_playback_rate(nsf_t * nsf)
{
  uint8 * p;
  unsigned int def, v;
  
  
  if (nsf->pal_ntsc_bits & NSF_DEDICATED_PAL) {
    p = (uint8*)&nsf->pal_speed;
    def = 50;
  } else {
    p = (uint8*)&nsf->ntsc_speed;
    def = 60;
  }
  v = p[0] | (p[1]<<8);
  return v ? 1000000 / v : def;
}

static int nsf_inited = 0;

static char * clean_string(char *d, const char *s, int max)
{
  int i;

  --max;
  for (i=0; i<max && s[i]; ++i) {
    d[i] = s[i];
  }
  for (; i<=max; ++i) {
    d[i] = 0;
  }

  return (char*)d;
}

static int get_integer(const char * arg, const char * opt, int * pv)
{
  char * end;
  long v;

  if (strstr(arg,opt) != arg) {
    return 1;
  }
  arg += strlen(opt);
  end = 0;
  v = strtol(arg, &end, 0);
  if (!end || *end) {
    return -1;
  }
  *pv = v;
  return 0;
}

static int get_string(const char * arg, const char * opt, char * v, int max)
{
  if (strstr(arg,opt) != arg) {
    return 1;
  }
  clean_string(v, arg + strlen(opt), max);
  return 0;
}

static int track_number(char **ps, int max)
{
  int n;
  if (!isdigit(**ps)) {
    return -1;
  }
  n = strtol(*ps, ps, 10);
  if (n<0 || n>max) {
    return -1;
  } else if (n==0) {
    n = max;
  }
  return n;
}

static int read_track_list(char **trackList, int max, int *from, int *to)
{
  int fromTrack, toTrack;
  char *t = *trackList;

  if (t) {
    /* Skip comma ',' */
    while(*t == ',') {
      ++t;
    }
  }

  /* Done with this list. */
  if (!t || !*t) {
/*     msg("track list finish here\n"); */
    *trackList = 0;
    return 0;
  }

/*   msg("parse:%s\n", t); */
  *trackList = t;
  fromTrack = track_number(trackList, max);

/*   msg("-> %d [%s]\n", fromTrack, *trackList); */

  if (fromTrack < 0) {
    return -1;
  }

  switch(**trackList) {
  case ',': case 0:
    toTrack = fromTrack;
    break;
  case '-':
    (*trackList)++;
    toTrack = track_number(trackList, max);
    if (toTrack < 0) {
      return -2;
    }
    break;
  default:
    return -1;
  }

  *from = fromTrack;
  *to   = toTrack;

/*   msg("from:%d, to:%d [%s]\n", fromTrack, toTrack, *trackList); */

  return 1;
}

void itoa(int n, char * res)
{
        if(n < 10)
        {
                res[0] = (char)(n) + '0';
                res[1] = '\0';
        }
        else if(n < 100)
        {
                res[0] = (char)(n/10) + '0';
                res[1] = (char)(n%10) + '0';
                res[2] = '\0';
        }
        else if(n < 1000)
        {
                res[0] = (char)(n/100) + '0';
                res[1] = (char)((n/10) % 10)+ '0';
                res[2] = (char)(n%10) + '0';
        }
        else
                {}
}
