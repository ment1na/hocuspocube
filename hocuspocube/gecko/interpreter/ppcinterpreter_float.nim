import
    ../ppcstate,
    math

using state: var PpcState

template fr(num: uint32): PairedSingle {.dirty.} = state.fr[num]

# TODO: handle more of these thousand float flags and exceptions

proc isNan[T: SomeFloat](x: T): bool = x != x

template setFprf(x: float64) {.dirty.} =
    state.fpscr.fprf = (case classify(x)
        of fcNormal: (if x < 0.0: 0b00100'u32 else: 0b01000'u32)
        of fcSubnormal: (if x < 0.0: 0b11000'u32 else: 0b10100'u32)
        of fcZero: 0b00010'u32
        of fcNegZero: 0b10010'u32
        of fcNan: 0b10001'u32
        of fcInf: 0b00101'u32
        of fcNegInf: 0b01001'u32)

template handleRc {.dirty.} =
    state.cr.ox = state.fpscr.ox
    state.cr.vx = state.fpscr.vx
    state.cr.fex = state.fpscr.fex
    state.cr.fx = state.fpscr.fx

proc faddx*(state; d, a, b, rc: uint32) =
    fr(d).double = fr(a).double + fr(b).double
    setFprf fr(d).double
    handleRc

proc faddsx*(state; d, a, b, rc: uint32) =
    fr(d).ps0 = fr(a).ps0 + fr(b).ps0
    fr(d).ps1 = fr(d).ps1
    setFprf fr(d).ps0
    handleRc

proc fdivx*(state; d, a, b, rc: uint32) =
    fr(d).double = fr(a).double / fr(b).double
    setFprf fr(d).double
    handleRc

proc fdivsx*(state; d, a, b, rc: uint32) =
    fr(d).ps0 = fr(a).ps0 / fr(b).ps0
    fr(d).ps1 = fr(d).ps0
    setFprf fr(d).ps0
    handleRc

proc fmulx*(state; d, a, c, rc: uint32) =
    fr(d).double = fr(a).double * fr(c).double
    setFprf fr(d).double
    handleRc

proc fmulsx*(state; d, a, c, rc: uint32) =
    fr(d).ps0 = fr(a).ps0 * fr(c).ps0
    fr(d).ps1 = fr(d).ps0
    setFprf fr(d).ps0
    handleRc

proc fresx*(state; d, b, rc: uint32) =
    doAssert false, "instr not implemented"

proc frsqrtex*(state; d, b, rc: uint32) =
    fr(d).double = 1.0 / sqrt(fr(b).double)
    setFprf fr(d).double
    handleRc

proc fsubx*(state; d, a, b, rc: uint32) =
    fr(d).double = fr(a).double - fr(b).double
    setFprf fr(d).double
    handleRc

proc fsubsx*(state; d, a, b, rc: uint32) =
    fr(d).ps0 = fr(a).ps0 - fr(b).ps0
    fr(d).ps1 = fr(d).ps0
    setFprf fr(d).ps0
    handleRc

proc fselx*(state; d, a, b, c, rc: uint32) =
    doAssert false, "instr not implemented"

proc fmaddx*(state; d, a, b, c, rc: uint32) =
    fr(d).double = fr(a).double * fr(c).double + fr(b).double
    setFprf fr(d).double
    handleRc

proc fmaddsx*(state; d, a, b, c, rc: uint32) =
    fr(d).ps0 = fr(a).ps0 * fr(c).ps0 + fr(b).ps0
    fr(d).ps1 = fr(d).ps0
    setFprf fr(d).ps0
    handleRc

proc fmsubx*(state; d, a, b, c, rc: uint32) =
    doAssert false, "instr not implemented"

proc fmsubsx*(state; d, a, b, c, rc: uint32) =
    doAssert false, "instr not implemented"

proc fnmaddx*(state; d, a, b, c, rc: uint32) =
    fr(d).double = -(fr(a).double * fr(c).double + fr(b).double)
    setFprf fr(d).double
    handleRc

proc fnmaddsx*(state; d, a, b, c, rc: uint32) =
    fr(d).ps0 = -(fr(a).ps0 * fr(c).ps0 + fr(b).ps0)
    fr(d).ps1 = fr(d).ps0
    setFprf fr(d).ps0
    handleRc

proc fnmsubx*(state; d, a, b, c, rc: uint32) =
    fr(d).double = -(fr(a).double * fr(c).double - fr(b).double)
    setFprf fr(d).double
    handleRc

proc fnmsubsx*(state; d, a, b, c, rc: uint32) =
    fr(d).ps0 = -(fr(a).ps0 * fr(c).ps0 - fr(b).ps0)
    fr(d).ps1 = fr(d).ps0
    setFprf fr(d).ps0
    handleRc

proc fctiwx*(state; d, b, rc: uint32) =
    doAssert false, "instr not implemented"

proc fctiwzx*(state; d, b, rc: uint32) =
    if fr(b).double > float64(high(int32)):
        fr(d).double = cast[float64](cast[uint64](high(int32)))
    elif fr(b).double < float64(low(int32)):
        fr(d).double = cast[float64](cast[uint64](low(int32)))
    else:
        fr(d).double = cast[float64](cast[uint64](int32(fr(b).double)))
    handleRc

proc frspx*(state; d, b, rc: uint32) =
    fr(d).ps0 = fr(b).double
    fr(d).ps1 = fr(d).ps0
    setFprf fr(d).ps0
    handleRc

proc fcmpo*(state; crfD, a, b: uint32) =
    state.cr.crf int crfD, 0'u32
    if isNan(fr(a).double) or isNan(fr(b).double):
        state.cr.so int crfD, true
    else:
        state.cr.eq int crfD, fr(a).double == fr(b).double
        state.cr.gt int crfD, fr(a).double > fr(b).double
        state.cr.lt int crfD, fr(a).double < fr(b).double

proc fcmpu*(state; crfD, a, b: uint32) =
    state.cr.crf int crfD, 0'u32
    if isNan(fr(a).double) or isNan(fr(b).double):
        state.cr.so int crfD, true
    else:
        state.cr.eq int crfD, fr(a).double == fr(b).double
        state.cr.gt int crfD, fr(a).double > fr(b).double
        state.cr.lt int crfD, fr(a).double < fr(b).double

proc mffsx*(state; d, rc: uint32) =
    fr(d).double = cast[float64](uint64(state.fpscr))
    handleRc

proc mtfsb0x*(state; crbD, rc: uint32) =
    state.fpscr.bit int crbD, false
    handleRc

proc mtfsb1x*(state; crbD, rc: uint32) =
    state.fpscr.bit int crbD, false
    handleRc

proc mtfsfx*(state; fm, b, rc: uint32) =
    echo "mtfsfx stubbed"

proc mtfsfix*(state; crfD, imm, rc: uint32) =
    echo "mtfsfix stubbed"

proc fabsx*(state; d, b, rc: uint32) =
    doAssert false, "instr not implemented"

proc fmrx*(state; d, b, rc: uint32) =
    fr(d).double = fr(b).double
    handleRc

proc fnabsx*(state; d, b, rc: uint32) =
    doAssert false, "instr not implemented"

proc fnegx*(state; d, b, rc: uint32) =
    fr(d).double = -fr(b).double
    handleRc

proc ps_div*(state; d, a, b, rc: uint32) =
    doAssert false, "instr not implemented"

proc ps_sub*(state; d, a, b, rc: uint32) =
    doAssert false, "instr not implemented"

proc ps_add*(state; d, a, b, rc: uint32) =
    doAssert false, "instr not implemented"

proc ps_sel*(state; d, a, b, c, rc: uint32) =
    doAssert false, "instr not implemented"

proc ps_res*(state; d, b, rc: uint32) =
    doAssert false, "instr not implemented"

proc ps_mul*(state; d, a, c, rc: uint32) =
    fr(d).ps0 = fr(a).ps0 * fr(c).ps0
    fr(d).ps1 = fr(a).ps1 * fr(c).ps1
    setFprf fr(d).ps0
    handleRc

proc ps_rsqrte*(state; d, b, rc: uint32) =
    doAssert false, "instr not implemented"

proc ps_msub*(state; d, a, b, c, rc: uint32) =
    fr(d).ps0 = fr(a).ps0 * fr(c).ps0 - fr(b).ps0
    fr(d).ps1 = fr(a).ps1 * fr(c).ps1 - fr(b).ps1
    setFprf fr(d).ps0
    handleRc

proc ps_madd*(state; d, a, b, c, rc: uint32) =
    fr(d).ps0 = fr(a).ps0 * fr(c).ps0 + fr(b).ps0
    fr(d).ps1 = fr(a).ps1 * fr(c).ps1 + fr(b).ps1
    setFprf fr(d).ps0
    handleRc

proc ps_nmsub*(state; d, a, b, c, rc: uint32) =
    doAssert false, "instr not implemented"

proc ps_nmadd*(state; d, a, b, c, rc : uint32) =
    doAssert false, "instr not implemented"

proc ps_neg*(state; d, b, rc: uint32) =
    fr(d).ps0 = -fr(b).ps0
    fr(d).ps1 = -fr(b).ps1
    handleRc

proc ps_mr*(state; d, b, rc: uint32) =
    fr(d).ps0 = fr(b).ps0
    fr(d).ps1 = fr(b).ps1
    handleRc

proc ps_nabs*(state; d, b, rc: uint32) =
    doAssert false, "instr not implemented"

proc ps_abs*(state; d, b, rc: uint32) =
    doAssert false, "instr not implemented"

proc ps_sum0*(state; d, a, b, c, rc: uint32) =
    fr(d).ps0 = fr(a).ps0 + fr(b).ps1
    fr(d).ps1 = fr(c).ps1
    setFprf fr(d).ps0
    handleRc

proc ps_sum1*(state; d, a, b, c, rc: uint32) =
    fr(d).ps0 = fr(c).ps0
    fr(d).ps1 = fr(a).ps0 + fr(b).ps1
    setFprf fr(d).ps0
    handleRc

proc ps_muls0*(state; d, a, c, rc: uint32) =
    fr(d).ps0 = fr(a).ps0 * fr(c).ps0
    fr(d).ps1 = fr(a).ps1 * fr(c).ps0
    setFprf fr(d).ps0
    handleRc

proc ps_muls1*(state; d, a, c, rc: uint32) =
    fr(d).ps0 = fr(a).ps0 * fr(c).ps1
    fr(d).ps1 = fr(a).ps1 * fr(c).ps1
    setFprf fr(d).ps0
    handleRc

proc ps_madds0*(state; d, a, b, c, rc: uint32) =
    fr(d).ps0 = fr(a).ps0 * fr(c).ps0 + fr(b).ps0
    fr(d).ps1 = fr(a).ps1 * fr(c).ps0 + fr(b).ps1
    setFprf fr(d).ps0
    handleRc

proc ps_madds1*(state; d, a, b, c, rc: uint32) =
    fr(d).ps0 = fr(a).ps0 * fr(c).ps1 + fr(b).ps0
    fr(d).ps1 = fr(a).ps1 * fr(c).ps1 + fr(b).ps1
    setFprf fr(d).ps0
    handleRc

proc ps_cmpu0*(state; crfD, a, b: uint32) =
    doAssert false, "instr not implemented"

proc ps_cmpo0*(state; crfD, a, b: uint32) =
    doAssert false, "instr not implemented"

proc ps_cmpu1*(state; crfD, a, b: uint32) =
    doAssert false, "instr not implemented"

proc ps_cmpo1*(state; crfD, a, b: uint32) =
    doAssert false, "instr not implemented"

proc ps_merge00*(state; d, a, b, rc: uint32) =
    fr(d).ps0 = fr(a).ps0
    fr(d).ps1 = fr(b).ps0
    handleRc

proc ps_merge01*(state; d, a, b, rc: uint32) =
    fr(d).ps0 = fr(a).ps0
    fr(d).ps1 = fr(b).ps1
    handleRc

proc ps_merge10*(state; d, a, b, rc: uint32) =
    fr(d).ps0 = fr(a).ps1
    fr(d).ps1 = fr(b).ps0
    handleRc

proc ps_merge11*(state; d, a, b, rc: uint32) =
    fr(d).ps0 = fr(a).ps1
    fr(d).ps1 = fr(b).ps1
    handleRc
