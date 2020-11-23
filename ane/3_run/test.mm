#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>

#import <IOSurface/IOSurfaceRef.h>

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

void hexdump(void *vdat, int l) {
  unsigned char *dat = (unsigned char *)vdat;
  for (int i = 0; i < l; i++) {
    if (i!=0 && (i%0x10) == 0) printf("\n");
    printf("%02X ", dat[i]);
  }
  printf("\n");
}

#include "h11ane.h"

using namespace H11ANE;

H11ANEDevice *device = NULL;

int MyH11ANEDeviceControllerNotification(H11ANEDeviceController *param_1, void *param_2, H11ANEDevice *param_3) {
  printf("MyH11ANEDeviceControllerNotification %p %p %p\n", param_1, param_2, param_3);
  device = param_3;
  return 0;
}

int MyH11ANEDeviceMessageNotification(H11ANE::H11ANEDevice* dev, unsigned int param_1, void* param_2, void* param_3) {
  printf("MyH11ANEDeviceMessageNotification %d %p %p\n", param_1, param_2, param_3);
  return 0;
}

int main() {
  printf("hello %d\n", getpid());
  int ret2, ret;

  H11ANEDeviceController *dc = new H11ANEDeviceController(MyH11ANEDeviceControllerNotification, NULL);
  dc->SetupDeviceController();
  // callback should have happened
  printf("%p %p\n", dc, device);

  H11ANEDevice *dev = device;
  printf("construct %p\n", dev);

  dev->EnableDeviceMessages();

  char empty[0x90];
  H11ANEDeviceInfoStruct dis = {0};
  ret = dev->H11ANEDeviceOpen(MyH11ANEDeviceMessageNotification, empty, UsageCompile, &dis);
  printf("open 0x%x %p\n", ret, dev);

  int is_powered;

  ret = dev->ANE_PowerOn();
  printf("power on: %d\n", ret);

  // need moar privilege
  /*unsigned int reg = 0;
  ret = dev->ANE_ReadANERegister(0, &reg);
  printf("reg 0x%x %lx\n", ret, reg);*/

  is_powered = dev->ANE_IsPowered();
  printf("powered? %d\n", is_powered);

  char *prog = (char*)aligned_alloc(0x1000, 0x8000);
  FILE *f = fopen("../2_compile/model.hwx", "rb");
  int sz = fread(prog, 1, 0x8000, f);
  printf("read %x %p\n", sz, prog);
  fclose(f);

  H11ANEProgramCreateArgsStruct mprog = {0};
  mprog.program = prog;
  mprog.program_length = 0x8000;

  H11ANEProgramCreateArgsStructOutput *out = new H11ANEProgramCreateArgsStructOutput;
  memset(out, 0, sizeof(H11ANEProgramCreateArgsStructOutput));
  ret = dev->ANE_ProgramCreate(&mprog, out);
  uint64_t program_handle = out->program_handle;
  printf("program create: %lx %lx\n", ret, program_handle);

  H11ANEProgramPrepareArgsStruct pas = {0};
  pas.program_handle = program_handle;
  pas.flags = 0x0000000100010001;
  ret = dev->ANE_ProgramPrepare(&pas);
  printf("program prepare: %lx\n", ret);

  H11ANEProgramRequestArgsStruct *pras = new H11ANEProgramRequestArgsStruct;
  memset(pras, 0, sizeof(H11ANEProgramRequestArgsStruct));

  // input buffer
  NSDictionary* dict = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSNumber numberWithInt:1], kIOSurfaceWidth,
                           [NSNumber numberWithInt:3], kIOSurfaceHeight,
                           [NSNumber numberWithInt:2], kIOSurfaceBytesPerElement,
                           [NSNumber numberWithInt:64], kIOSurfaceBytesPerRow,
                           [NSNumber numberWithInt:1278226536], kIOSurfacePixelFormat,
                           nil];
  IOSurfaceRef in_surf = IOSurfaceCreate((CFDictionaryRef)dict);
  int in_surf_id = IOSurfaceGetID(in_surf);
  printf("we have surface %p with id 0x%x\n", in_surf, in_surf_id);

  // output buffer
  NSDictionary* odict = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSNumber numberWithInt:1], kIOSurfaceWidth,
                           [NSNumber numberWithInt:2], kIOSurfaceHeight,
                           [NSNumber numberWithInt:2], kIOSurfaceBytesPerElement,
                           [NSNumber numberWithInt:64], kIOSurfaceBytesPerRow,
                           [NSNumber numberWithInt:1278226536], kIOSurfacePixelFormat,
                           nil];
  IOSurfaceRef out_surf = IOSurfaceCreate((CFDictionaryRef)odict);
  int out_surf_id = IOSurfaceGetID(out_surf);
  printf("we have surface %p with id 0x%x\n", out_surf, out_surf_id);

  // TODO: make real struct
  pras->args[0] = out->program_handle;
  pras->args[4] = 0x0000002100000003;

  // inputs
  pras->args[0x28/8] = 1;
  pras->args[0x128/8] = (long long)in_surf_id<<32LL;

  // outputs
  pras->args[0x528/8] = 1;
  // 0x628 = outputBufferSurfaceId
  pras->args[0x628/8] = (long long)out_surf_id<<32LL;

  mach_port_t recvPort = 0;
  IOCreateReceivePort(0x39, &recvPort);
  printf("recv port: 0x%x\n", recvPort);

  ret = dev->ANE_ProgramSendRequest(pras, recvPort);
  printf("send 0x%x\n", ret);

  // TODO: wait for message on recvPort
  usleep(100*1000);

  unsigned char *dat = (unsigned char *)IOSurfaceGetBaseAddress(out_surf);
  printf("%p\n", dat);
  hexdump(dat, 0x100);
}


