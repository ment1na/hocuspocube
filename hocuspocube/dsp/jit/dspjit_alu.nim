import
    options, stew/bitops2,
    ../../util/[jit/ir, aluhelper], ../dspstate,
    dspfrontendcommon,
    dspjit_secondary,
    fallbacks

using builder: var IrBlockBuilder[DspIrState]

const interpretAlu = false

proc addAccumOp(builder; accumN: uint32, addend: IrInstrRef, secondary: Option[uint16]) =
    let accum = builder.readAccum(accumN)

    if secondary.isSome:
        builder.dispatchSecondary(secondary.get)

    let
        sum = builder.biop(iAddX, accum, addend)
        ov = builder.biop(overflowAddX, accum, addend)
        ca = builder.biop(carryAddX, accum, addend)
    builder.writeStatus(dspStatusBitOv, ov)
    builder.writeStatus(dspStatusBitCa, ca)

    let sum40 = builder.signExt40(sum)
    builder.setZ1(sum40)
    builder.setN1(sum40)
    builder.setE1(sum40)
    builder.setU1(sum40)

    builder.writeAccum(accumN, sum40)

proc subAccumOp(builder; accumN: uint32, subtrahend: IrInstrRef, secondary: Option[uint16], cmp: bool) =
    let accum = builder.readAccum(accumN)

    if secondary.isSome:
        builder.dispatchSecondary(secondary.get)

    let
        diff = builder.biop(iSubX, accum, subtrahend)
        ov = builder.biop(overflowSubX, accum, subtrahend)
        ca = builder.biop(carrySubX, accum, subtrahend)
    builder.writeStatus(dspStatusBitOv, ov)
    builder.writeStatus(dspStatusBitCa, ca)

    let diff40 = builder.signExt40(diff)
    builder.setZ1(diff40)
    builder.setN1(diff40)
    builder.setE1(diff40)
    builder.setU1(diff40)

    if not cmp:
        builder.writeAccum(accumN, diff40)

proc logicOp(builder; accumN: uint32, op: InstrKind, operand: IrInstrRef, secondary: Option[uint16]) =
    let accum = builder.readAccum(accumN, {a1.succ(int accumN), a2.succ(int accumN)})

    if secondary.isSome:
        builder.dispatchSecondary(secondary.get)

    let
        res = builder.biop(op, accum, operand)
        zero = builder.biop(iCmpEqualX, res, builder.imm(0))
        mi = builder.biop(iCmpLessSX, res, builder.imm(0))

    builder.writeStatus(dspStatusBitOv, builder.imm(false))
    builder.writeStatus(dspStatusBitCa, builder.imm(false))
    builder.setZ2(zero)
    builder.setN2(mi)
    builder.setE1(res)
    builder.setU1(res)

    builder.writeAccum(accumN, res, {a1.succ(int accumN)})

proc mr*(builder; m, r: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.mr)
    else:
        if m != 0:
            let
                adr = builder.readAdr(r)
                wrap = builder.readAdrLen(r)
            case range[0..7](m)
            of 0: discard
            of 1: builder.writeAdr r, builder.decAdr(adr, wrap)
            of 2: builder.writeAdr r, builder.incAdr(adr, wrap)
            of 3: builder.writeAdr r, builder.decAdr(adr, wrap, builder.readAdrMod(r))
            of 4..7: builder.writeAdr r, builder.incAdr(adr, wrap, builder.readAdrMod(m-4))

proc adsi*(builder; d, i: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.adsi)
    else:
        builder.addAccumOp(d, builder.imm(signExtend[uint64](i, 8) shl 16), none(uint16))

proc adli*(builder; d: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.adli)
        discard builder.fetchFollowingImm
    else:
        builder.addAccumOp(d, builder.imm(signExtend[uint64](builder.fetchFollowingImm(), 16) shl 16), none(uint16))

proc cmpsi*(builder; s, i: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.cmpsi)
    else:
        builder.subAccumOp(s, builder.imm(signExtend[uint64](i, 8) shl 16), none(uint16), true)

proc cmpli*(builder; s: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.cmpli)
        discard builder.fetchFollowingImm
    else:
        builder.subAccumOp(s, builder.imm(signExtend[uint64](builder.fetchFollowingImm, 16) shl 16), none(uint16), true)

proc lsfi*(builder; d, i: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.lsfi)

proc asfi*(builder; d, i: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.asfi)

proc xorli*(builder; d: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.xorli)
        discard builder.fetchFollowingImm
    else:
        builder.logicOp(d, bitXorX, builder.imm(uint64(builder.fetchFollowingImm()) shl 16), none(uint16))

proc anli*(builder; d: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.anli)
        discard builder.fetchFollowingImm
    else:
        builder.logicOp(d, bitAndX, builder.imm((uint64(builder.fetchFollowingImm()) shl 16) or 0xFFFF_FFFF_0000_FFFF'u64), none(uint16))

proc orli*(builder; d: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.orli)
        discard builder.fetchFollowingImm
    else:
        builder.logicOp(d, bitOrX, builder.imm(uint64(builder.fetchFollowingImm()) shl 16), none(uint16))

proc norm*(builder; d, r: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.norm)

proc ddiv*(builder; d, s: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.ddiv)

proc addc*(builder; d, s: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.addc)

proc subc*(builder; d, s: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.subc)

proc negc*(builder; d: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.negc)

proc max*(builder; d, s: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.max)

proc lsfn*(builder; d, s: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.lsfn)

proc lsfn2*(builder; d: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.lsfn2)

proc asfn*(builder; d, s: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.asfn)

proc asfn2*(builder; d: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.asfn2)

proc mv*(builder; d, s: uint16) =
    if interpretAlu or DspReg(d) in DspReg.pcs..DspReg.lcs or
        DspReg(s) in DspReg.pcs..DspReg.lcs:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.mv)
    else:
        builder.writeReg(DspReg d, builder.readReg(DspReg s))

proc mvsi*(builder; d, i: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.mvsi)
    else:
        if d <= 5:
            builder.writeReg(x0.succ(int d), builder.imm(signExtend(i, 8)))
        else:
            builder.loadAccum(d - 6, builder.imm(signExtend(i, 8)))

proc mvli*(builder; d: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.mvli)
        discard builder.fetchFollowingImm()
    else:
        builder.writeReg(DspReg(d), builder.imm(builder.fetchFollowingImm()))

proc clrpsr*(builder; b: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.clrpsr)
    else:
        builder.writeStatus(dspStatusBitTb.succ(int b), builder.imm(false))

proc setpsr*(builder; b: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.setpsr)
    else:
        builder.writeStatus(dspStatusBitTb.succ(int b), builder.imm(true))

proc btstl*(builder; b: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.btstl)
        discard builder.fetchFollowingImm()
    else:
        let mask = builder.imm(uint32(builder.fetchFollowingImm()) shl 16)
        builder.writeStatus(dspStatusBitTb,
            builder.biop(iCmpEqual,
                builder.biop(bitAnd, builder.readAccum(b, {a1.succ(int b)}), mask),
                builder.imm(0)))

proc btsth*(builder; b: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.btsth)
        discard builder.fetchFollowingImm()
    else:
        let mask = builder.imm(uint32(builder.fetchFollowingImm()) shl 16)
        builder.writeStatus(dspStatusBitTb,
            builder.biop(iCmpEqual,
                builder.biop(bitAnd, builder.readAccum(b, {a1.succ(int b)}), mask),
                mask))

proc getAddSubParam(builder; d, s: uint16): IrInstrRef =
    case range[0..7](s)
    of 0..1: builder.biop(lsl, builder.unop(extsh, builder.readReg(x0.succ(int s))), builder.imm(16))
    of 2..3: builder.biop(bitAnd, builder.readAuxAccum(s-2), builder.imm(not 0xFFFF'u64))
    of 4..5: builder.readAuxAccum(s - 4)
    of 6: builder.readAccum(1 - d)
    of 7: builder.readProd()

proc add*(builder; s, d, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.add)
    else:
        builder.addAccumOp(d, builder.getAddSubParam(d, s), some(x))

proc addl*(builder; s, d, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.addl)
    else:
        builder.addAccumOp(d, builder.readReg(x0.succ(int s)), some(x))

proc sub*(builder; s, d, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.sub)
    else:
        builder.subAccumOp(d, builder.getAddSubParam(d, s), some(x), false)

proc amv*(builder; s, d, x: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.amv)

proc cmp*(builder; s, d, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.cmp)
    else:
        builder.subAccumOp(d, builder.biop(bitandX, builder.readAuxAccum(s), builder.imm(not 0xFFFF'u64)), some(x), true)

proc cmpa*(builder; x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.cmpa)
    else:
        builder.subAccumOp(0, builder.readAccum(1), some(x), true)

proc inc*(builder; d, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.inc)
    else:
        builder.addAccumOp(uint32 d.getBit(0), builder.imm(if d.getBit(1): 1 else: 0x10000), some(x))

proc dec*(builder; d, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.dec)
    else:
        builder.subAccumOp(uint32 d.getBit(0), builder.imm(if d.getBit(1): 1 else: 0x10000), some(x), false)

proc abs*(builder; d, x: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.abs)

proc neg*(builder; d, x: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.neg)

proc negp*(builder; d, x: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.negp)

proc clra*(builder; d, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.clra)
    else:
        builder.dispatchSecondary(x)

        builder.writeStatus dspStatusBitCa, builder.imm(false)
        builder.writeStatus dspStatusBitOv, builder.imm(false)
        builder.writeStatus dspStatusBitZr, builder.imm(true)
        builder.writeStatus dspStatusBitMi, builder.imm(false)
        builder.writeStatus dspStatusBitExt, builder.imm(false)
        builder.writeStatus dspStatusBitUnnorm, builder.imm(false)
        builder.writeAccum d, builder.imm(0)

proc clrp*(builder; x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.clrp)
    else:
        builder.dispatchSecondary(x)

        builder.writeProdParts(builder.imm(0xFFFF_FFFF_FFF0_0000'u64))
        builder.writeProdCarry(builder.imm(0x0010))

proc round(builder): IrInstrRef =
    discard

proc rnd*(builder; d, x: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.rnd)

proc rndp*(builder; d, x: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.rndp)

proc tst*(builder; s, x: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.tst)

proc tst2*(builder; s, x: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.tst2)

proc tstp*(builder; x: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.tstp)

proc lsl16*(builder; d, x: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.lsl16)

proc lsr16*(builder; d, x: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.lsr16)

proc asr16*(builder; d, x: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.asr16)

proc addp*(builder; s, d, x: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.addp)

proc pnop*(builder; x: uint16) =
    builder.dispatchSecondary(x)

proc clrim*(builder; x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.clrim)
    else:
        builder.dispatchSecondary(x)
        builder.writeStatus dspStatusBitIm, builder.imm(false)

proc clrdp*(builder; x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.clrdp)
    else:
        builder.dispatchSecondary(x)
        builder.writeStatus dspStatusBitDp, builder.imm(false)

proc clrxl*(builder; x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.clrxl)
    else:
        builder.dispatchSecondary(x)
        builder.writeStatus dspStatusBitXl, builder.imm(false)

proc setim*(builder; x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.setim)
    else:
        builder.dispatchSecondary(x)
        builder.writeStatus dspStatusBitIm, builder.imm(true)

proc setdp*(builder; x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.setdp)
    else:
        builder.dispatchSecondary(x)
        builder.writeStatus dspStatusBitDp, builder.imm(true)

proc setxl*(builder; x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.setxl)
    else:
        builder.dispatchSecondary(x)
        builder.writeStatus dspStatusBitXl, builder.imm(true)

proc getMulOperands(builder; s: uint16): (IrInstrRef, IrInstrRef, bool, bool) =
    case range[2..11](s)
    of 2: (builder.readReg(x1), builder.readReg(x0), false, false)
    of 3: (builder.readReg(y1), builder.readReg(y0), false, false)
    of 4: (builder.readReg(x0), builder.readReg(y0), true, true)
    of 5: (builder.readReg(x0), builder.readReg(y1), true, false)
    of 6: (builder.readReg(x1), builder.readReg(y0), false, true)
    of 7: (builder.readReg(x1), builder.readReg(y1), false, false)
    of 8: (builder.readReg(a1), builder.readReg(x1), false, false)
    of 9: (builder.readReg(a1), builder.readReg(y1), false, false)
    of 10: (builder.readReg(b1), builder.readReg(x1), false, false)
    of 11: (builder.readReg(b1), builder.readReg(y1), false, false)

proc doMul(builder; a, b: IrInstrRef, aDpUnsigned, bDpUnsigned: bool): IrInstrRef =
    let
        dp = builder.readStatus dspStatusBitDp

        aSigned =
            if aDpUnsigned:
                builder.triop(cselX, a, builder.unop(extshX, a), dp)
            else:
                builder.unop(extshX, a)
        bSigned =
            if bDpUnsigned:
                builder.triop(cselX, b, builder.unop(extshX, b), dp)
            else:
                builder.unop(extshX, b)

        im = builder.readStatus dspStatusBitIm

    builder.biop(iMulX, aSigned, builder.triop(cselX, bSigned, builder.biop(lslX, bSigned, builder.imm(1)), im))

proc mpy*(builder; s, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.mpy)
    else:
        let
            (a, b, aDpUnsigned, bDpUnsigned) = builder.getMulOperands(s)
            prod = builder.doMul(a, b, aDpUnsigned, bDpUnsigned)

        builder.dispatchSecondary(x)

        builder.writeProd(prod)

proc mpy2*(builder; x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.mpy2)
    else:
        let
            factor = builder.readReg(x1)
            prod = builder.doMul(factor, factor, false, false)

        builder.dispatchSecondary(x)

        builder.writeProd(prod)

proc macOp(builder; a, b: IrInstrRef, negate: bool, x: uint16) =
    let
        aVal = builder.unop(extshX, a)
        bVal = builder.unop(extshX, b)

        im = builder.readStatus dspStatusBitIm

        prod = builder.biop(iMulX, aVal, builder.triop(cselX, bVal, builder.biop(lslX, bVal, builder.imm(1)), im))
        sum = builder.signExt40(builder.biop(if negate: iSubX else: iAddX, builder.readProd(), prod))

    builder.dispatchSecondary(x)

    builder.writeProd(sum)

proc mac*(builder; s, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.mac)
    else:
        builder.macOp(
            builder.readReg(x0.succ(int(s.getBit(1))*2)),
            builder.readReg(y0.succ(int(s.getBit(0))*2)),
            false, x)

proc mac2*(builder; s, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.mac2)
    else:
        builder.macOp(
            builder.readReg(a1.succ(int s.getBit(1))),
            builder.readReg(x1.succ(int s.getBit(0))),
            false, x)

proc mac3*(builder; s, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.mac3)
    else:
        builder.macOp(
            builder.readReg(x1.succ(int s)),
            builder.readReg(x0.succ(int s)),
            false, x)

proc macn*(builder; s, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.macn)
    else:
        builder.macOp(
            builder.readReg(x0.succ(int(s.getBit(1))*2)),
            builder.readReg(y0.succ(int(s.getBit(0))*2)),
            true, x)

proc macn2*(builder; s, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.macn2)
    else:
        builder.macOp(
            builder.readReg(a1.succ(int s.getBit(1))),
            builder.readReg(x1.succ(int s.getBit(0))),
            true, x)

proc macn3*(builder; s, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.macn3)
    else:
        builder.macOp(
            builder.readReg(x1.succ(int s)),
            builder.readReg(x0.succ(int s)),
            true, x)

proc mvmpy*(builder; s, d, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.mvmpy)
    else:
        let
            oldProd = builder.readProd()
            (a, b, aDpUnsigned, bDpUnsigned) = builder.getMulOperands(s)
            prod = builder.doMul(a, b, aDpUnsigned, bDpUnsigned)

        builder.dispatchSecondary(x)

        builder.writeAccum(d, oldProd)
        builder.writeProd(prod)
        builder.writeStatus dspStatusBitCa, builder.imm(false)
        builder.writeStatus dspStatusBitOv, builder.imm(false)
        builder.setZ1(oldProd)
        builder.setN1(oldProd)
        builder.setE1(oldProd)
        builder.setU1(oldProd)

proc rnmpy*(builder; s, d, x: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.rnmpy)

proc admpy*(builder; s, d, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.admpy)
    else:
        let
            oldProd = builder.readProd()
            accum = builder.readAccum(d)
            (a, b, aDpUnsigned, bDpUnsigned) = builder.getMulOperands(s)
            prod = builder.doMul(a, b, aDpUnsigned, bDpUnsigned)

        builder.dispatchSecondary(x)

        builder.writeProd(prod)
        let
            sum = builder.biop(iAddX, accum, oldProd)
            ov = builder.biop(overflowAddX, accum, oldProd)
            ca = builder.biop(carryAddX, accum, oldProd)
        builder.writeStatus(dspStatusBitOv, ov)
        builder.writeStatus(dspStatusBitCa, ca)

        let sum40 = builder.signExt40(sum)
        builder.setZ1(sum40)
        builder.setN1(sum40)
        builder.setE1(sum40)
        builder.setU1(sum40)
        builder.writeAccum(d, sum40)

proc nnot*(builder; d, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.nnot)
    else:
        builder.logicOp(d, bitXorX, builder.imm(0xFFFF_0000'u64), some(x))

proc xxor*(builder; s, d, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.xxor)
    else:
        builder.logicOp(d, bitXorX, builder.biop(bitAndX, builder.readAuxAccum(s), builder.imm(0xFFFF_0000'u64)), some(x))

proc xxor2*(builder; d, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.xxor2)
    else:
        builder.logicOp(d, bitXorX, builder.biop(bitAndX, builder.readAccum(1-d), builder.imm(0xFFFF_0000'u64)), some(x))

proc aand*(builder; s, d, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.aand)
    else:
        builder.logicOp(d, bitAndX, builder.biop(bitOrX, builder.readAuxAccum(s), builder.imm(0xFFFF_FFFF_0000_FFFF'u64)), some(x))

proc aand2*(builder; d, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.aand2)
    else:
        builder.logicOp(d, bitAndX, builder.biop(bitOrX, builder.readAccum(1-d), builder.imm(0xFFFF_FFFF_0000_FFFF'u64)), some(x))

proc oor*(builder; s, d, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.oor)
    else:
        builder.logicOp(d, bitOrX, builder.biop(bitAndX, builder.readAuxAccum(s), builder.imm(0xFFFF_0000'u64)), some(x))

proc oor2*(builder; d, x: uint16) =
    when interpretAlu:
        builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.oor2)
    else:
        builder.logicOp(d, bitXorX, builder.biop(bitAndX, builder.readAccum(1-d), builder.imm(0xFFFF_0000'u64)), some(x))

proc lsf*(builder; s, d, x: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.lsf)

proc lsf2*(builder; d, x: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.lsf2)

proc asf*(builder; s, d, x: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.asf)

proc asf2*(builder; d, x: uint16) =
    builder.interpretdsp(builder.regs.instr, builder.regs.pc, fallbacks.asf2)

