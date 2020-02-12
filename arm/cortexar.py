# BSP support for Cortex-A/R
from support.bsp_sources.archsupport import ArchSupport
from support.bsp_sources.target import DFBBTarget


class CortexARArch(ArchSupport):
    @property
    def name(self):
        return "cortex-ar"

    def __init__(self):
        super(CortexARArch, self).__init__()
        self.add_gnat_sources(
            'src/i-arm_v7ar.ads',
            'src/i-arm_v7ar.adb',
            'src/i-cache.ads',
            'src/i-cache__armv7.adb')
        self.add_gnarl_sources(
            'src/s-bbcpsp__arm.ads',
            'src/s-bbcppr__new.ads',
            'src/s-bbinte__generic.adb')


class CortexAArch(ArchSupport):
    @property
    def name(self):
        return "cortex-a"

    @property
    def parent(self):
        return CortexARArch

    def __init__(self):
        super(CortexAArch, self).__init__()
        self.add_gnarl_source('src/s-bbcppr__arm.adb')


class CortexRArch(ArchSupport):
    @property
    def name(self):
        return "cortex-r"

    @property
    def parent(self):
        return CortexARArch

    def __init__(self):
        super(CortexRArch, self).__init__()
        self.add_gnarl_source('src/s-bbcppr__armv7r.adb')


class CortexATarget(DFBBTarget):
    @property
    def target(self):
        return 'arm-eabi'

    @property
    def parent(self):
        return CortexAArch

    @property
    def has_timer_64(self):
        return True

    @property
    def zfp_system_ads(self):
        return 'system-xi-arm.ads'

    def amend_rts(self, rts_profile, conf):
        super(CortexATarget, self).amend_rts(rts_profile, conf)
        # s-bbcppr.adb uses the r7 register during context switching: this
        # is not compatible with the use of frame pointers that is emited at
        # -O0 by gcc. Let's disable fp even at -O0.
        if 'ravenscar' in rts_profile:
            conf.build_flags['common_flags'] += ['-fomit-frame-pointer']


class CortexRTarget(CortexATarget):
    @property
    def parent(self):
        return CortexRArch


class Rpi2Base(CortexATarget):
    @property
    def loaders(self):
        return ('RAM', )

    @property
    def mcu(self):
        return 'cortex-a7'

    @property
    def fpu(self):
        return 'vfpv4'

    @property
    def compiler_switches(self):
        # The required compiler switches
        return ('-mlittle-endian', '-mhard-float',
                '-mcpu=%s' % self.mcu,
                '-mfpu=%s' % self.fpu,
                '-marm', '-mno-unaligned-access')

    @property
    def readme_file(self):
        return 'arm/rpi2/README'

    @property
    def sfp_system_ads(self):
        return 'system-xi-arm-sfp.ads'

    @property
    def full_system_ads(self):
        return 'system-xi-arm-full.ads'

    def __init__(self):
        super(Rpi2Base, self).__init__()

        self.add_linker_script('arm/rpi2/ram.ld', loader='RAM')
        self.add_gnat_sources(
            'src/i-raspberry_pi.ads',
            'src/s-macres__rpi2.adb')
        self.add_gnarl_sources(
            'src/a-intnam__rpi2.ads',
            'src/s-bbbosu__rpi2.adb')


class Rpi2(Rpi2Base):
    @property
    def name(self):
        return "rpi2"

    def __init__(self):
        super(Rpi2, self).__init__()

        self.add_gnat_sources(
            'arm/rpi2/start-ram.S',
            'arm/rpi2/memmap.s',
            'src/s-textio__rpi2-mini.adb')
        self.add_gnarl_sources(
            'src/s-bbpara__rpi2.ads')


class Rpi2Mc(Rpi2Base):
    @property
    def name(self):
        return "rpi2mc"

    def __init__(self):
        super(Rpi2Mc, self).__init__()

        self.add_gnat_sources(
            'arm/rpi2-mc/start-ram.S',
            'arm/rpi2-mc/memmap.s',
            'src/s-textio__rpi2-pl011.adb')
        self.add_gnarl_sources(
            'src/s-bbpara__rpi2.ads')


class TMS570(CortexRTarget):
    @property
    def name(self):
        if self.variant == 'tms570ls31':
            base = 'tms570'
        else:
            base = 'a6mc'

        if self.uart_io:
            return "%s_sci" % base
        else:
            return base

    @property
    def has_small_memory(self):
        return True

    @property
    def loaders(self):
        return ('LORAM', 'FLASH', 'HIRAM')

    @property
    def cpu(self):
        if self.variant == 'tms570ls31':
            return 'cortex-r4f'
        else:
            return 'cortex-r5'

    @property
    def compiler_switches(self):
        # The required compiler switches
        return ('-mbig-endian', '-mhard-float', '-mcpu=%s' % self.cpu,
                '-mfpu=vfpv3-d16', '-marm')

    @property
    def readme_file(self):
        return 'arm/tms570/README'

    @property
    def system_ads(self):
        return {'zfp': self.zfp_system_ads,
                'ravenscar-sfp': 'system-xi-armv7r-sfp.ads',
                'ravenscar-full': 'system-xi-armv7r-full.ads'}

    def add_linker_scripts(self):
        self.add_linker_script('arm/tms570/common.ld')
        self.add_linker_script(
            'arm/tms570/%s.ld' % self.variant, dst='tms570.ld')
        self.add_linker_script('arm/tms570/flash.ld', loader='FLASH')
        self.add_linker_script('arm/tms570/hiram.ld', loader='HIRAM')
        self.add_linker_script('arm/tms570/loram.ld', loader='LORAM')
        self.add_linker_switch('-Wl,-z,max-page-size=0x1000',
                               loader=['FLASH', 'HIRAM', 'LORAM',
                                       'BOOT'])

    def __init__(self, variant='tms570ls31', uart_io=False):
        self.variant = variant
        self.uart_io = uart_io
        super(TMS570, self).__init__()

        self.add_linker_scripts()

        self.add_gnat_sources(
            'arm/tms570/crt0.S',
            'arm/tms570/system_%s.c' % self.variant,
            'arm/tms570/s-tms570.ads', 'arm/tms570/s-tms570.adb',
            'src/s-macres__tms570.adb')
        if self.cpu == 'cortex-r4f':
            self.add_gnat_source('arm/tms570/cortex-r4.S')
        if self.uart_io:
            self.add_gnat_source('src/s-textio__tms570-sci.adb')
        else:
            self.add_gnat_source('src/s-textio__tms570.adb')

        self.add_gnarl_sources(
            'src/a-intnam__%s.ads' % self.variant,
            'src/s-bbpara__%s.ads' % self.variant,
            'src/s-bbbosu__tms570.adb',
            'src/s-bbsumu__generic.adb')


class Zynq7000(CortexATarget):
    @property
    def name(self):
        return "zynq7000"

    @property
    def loaders(self):
        return ('RAM', )

    @property
    def mcu(self):
        return 'cortex-a9'

    @property
    def fpu(self):
        return 'vfpv3'

    @property
    def compiler_switches(self):
        # The required compiler switches
        return ('-mlittle-endian', '-mhard-float',
                '-mcpu=%s' % self.mcu,
                '-mfpu=%s' % self.fpu,
                '-marm', '-mno-unaligned-access')

    @property
    def readme_file(self):
        return 'arm/zynq/README'

    @property
    def sfp_system_ads(self):
        return 'system-xi-arm-gic-sfp.ads'

    @property
    def full_system_ads(self):
        return 'system-xi-arm-gic-full.ads'

    def __init__(self):
        super(Zynq7000, self).__init__()
        self.add_linker_script('arm/zynq/ram.ld', loader='RAM')
        self.add_gnat_sources(
            'arm/zynq/start-ram.S',
            'arm/zynq/memmap.inc',
            'src/s-textio__zynq.adb',
            'src/s-macres__zynq.adb')
        self.add_gnarl_sources(
            'src/a-intnam__zynq.ads',
            'src/s-bbpara__cortexa9.ads',
            'src/s-bbbosu__cortexa9.adb')
