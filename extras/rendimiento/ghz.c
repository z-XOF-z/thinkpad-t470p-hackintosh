#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <mach/mach_time.h>
#include <time.h>
/* Mide con el tiempo de CPU del propio hilo (no el reloj de pared): si otro proceso le quita turnos, no cuenta. */
static double ahora(void){ struct timespec t; clock_gettime(CLOCK_THREAD_CPUTIME_ID,&t); return t.tv_sec+t.tv_nsec/1e9; }
static double medir(void){ unsigned long n=2000000000UL; uint64_t a;
 double t0=ahora();
 __asm__ volatile("mov %1,%%rcx\n1:\nadd $1,%0\nadd $1,%0\nadd $1,%0\nadd $1,%0\nsub $4,%%rcx\njnz 1b":"=r"(a):"r"(n):"rcx");
 double s=ahora()-t0; return n/s/1e9; }
static void* hilo(void*p){ *(double*)p=medir(); return 0; }
int main(int c,char**v){ int k=atoi(v[1]); pthread_t t[8]; double r[8];
 for(int i=0;i<k;i++) pthread_create(&t[i],0,hilo,&r[i]);
 for(int i=0;i<k;i++) pthread_join(t[i],0);
 for(int i=0;i<k;i++) printf("%.2f GHz  ",r[i]); printf("\n"); }
