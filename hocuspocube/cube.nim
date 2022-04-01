import
    streams, strformat,
    gekko/[interpreter/ppcinterpreter, gekko, ppcstate, memory],
    dsp/interpreter/dspinterpreter

when not defined(nintendoswitch):
    import gekko/jit/ppcfrontend, dsp/jit/dspfrontend

import
    flipper/[rasterinterface, cp],
    util/dolfile,
    cycletiming,

    vi,

    std/monotimes, times

when defined(nintendoswitch):
    import frontend/switch
else:
    import frontend/sdl

proc loadDol*(input: Stream) =
    let file = dolfile.loadDol(input)

    proc writeSection(section: Section) =
        writeMainRAM(section.start - 0x80000000'u32, section.data)
    for section in file.text:
        echo &".text at {section.start:X}"
        writeSection section
    for section in file.data:
        echo &".data at {section.start:X}"
        writeSection section

    gekkoState.pc = file.entrypoint - 0x80000000'u32

proc boot*() =
    gekkoState.msr.ip = true
    gekkoState.pendingExceptions.incl exceptionSystemReset

proc run*() =
    rasterinterface.init()
    while frontendRunning:
        gekkoTarget = min(gekkoTimestamp + gekkoMaxSlice, nearestEvent())
        let gekkoStart = getMonoTime()
        ppcinterpreter.gekkoRun gekkoTimestamp, gekkoTarget
        let dspStart = getMonoTime()
        dspinterpreter.dspRun dspTimestamp, gekkoTimestamp
        let dspEnd = getMonoTime()
        gekkoTime += dspStart - gekkoStart
        dspTime += dspEnd - dspStart

        cpRun()

        processEvents()
