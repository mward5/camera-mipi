/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20260408 (32-bit version)
 * Copyright (c) 2000 - 2026 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of ssdt2.dat
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x00004091 (16529)
 *     Revision         0x02
 *     Checksum         0xE8
 *     OEM ID           "DptfTb"
 *     OEM Table ID     "DptfTabl"
 *     OEM Revision     0x00001000 (4096)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20200717 (538969879)
 */
DefinitionBlock ("", "SSDT", 2, "DptfTb", "DptfTabl", 0x00001000)
{
    External (_SB_.AAC0, FieldUnitObj)
    External (_SB_.ACRT, FieldUnitObj)
    External (_SB_.APSV, FieldUnitObj)
    External (_SB_.CBMI, FieldUnitObj)
    External (_SB_.CFGD, FieldUnitObj)
    External (_SB_.CLVL, FieldUnitObj)
    External (_SB_.CPPC, FieldUnitObj)
    External (_SB_.CTC0, FieldUnitObj)
    External (_SB_.CTC1, FieldUnitObj)
    External (_SB_.CTC2, FieldUnitObj)
    External (_SB_.OSCP, IntObj)
    External (_SB_.PAGD, DeviceObj)
    External (_SB_.PAGD._PUR, PkgObj)
    External (_SB_.PAGD._STA, MethodObj)    // 0 Arguments
    External (_SB_.PC00, DeviceObj)
    External (_SB_.PC00.LPCB.ECDV, DeviceObj)
    External (_SB_.PC00.LPCB.ECDV.AMBF, DeviceObj)
    External (_SB_.PC00.LPCB.ECDV.CHRG, DeviceObj)
    External (_SB_.PC00.LPCB.ECDV.DPRT, MethodObj)    // 0 Arguments
    External (_SB_.PC00.LPCB.ECDV.DSRQ, MethodObj)    // 0 Arguments
    External (_SB_.PC00.LPCB.ECDV.DSSQ, MethodObj)    // 1 Arguments
    External (_SB_.PC00.LPCB.ECDV.ECR1, MethodObj)    // 1 Arguments
    External (_SB_.PC00.LPCB.ECDV.ECW1, MethodObj)    // 2 Arguments
    External (_SB_.PC00.LPCB.ECDV.NGFF, DeviceObj)
    External (_SB_.PC00.LPCB.ECDV.TMEM, DeviceObj)
    External (_SB_.PC00.LPCB.ECDV.TSKN, DeviceObj)
    External (_SB_.PC00.LPCB.H_EC.UVTH, FieldUnitObj)
    External (_SB_.PC00.MC__.MHBR, FieldUnitObj)
    External (_SB_.PC00.TCPU, DeviceObj)
    External (_SB_.PL10, FieldUnitObj)
    External (_SB_.PL11, FieldUnitObj)
    External (_SB_.PL12, FieldUnitObj)
    External (_SB_.PL20, FieldUnitObj)
    External (_SB_.PL21, FieldUnitObj)
    External (_SB_.PL22, FieldUnitObj)
    External (_SB_.PLW0, FieldUnitObj)
    External (_SB_.PLW1, FieldUnitObj)
    External (_SB_.PLW2, FieldUnitObj)
    External (_SB_.PR00, ProcessorObj)
    External (_SB_.PR00._PSS, MethodObj)    // 0 Arguments
    External (_SB_.PR00._TPC, IntObj)
    External (_SB_.PR00._TSD, MethodObj)    // 0 Arguments
    External (_SB_.PR00._TSS, MethodObj)    // 0 Arguments
    External (_SB_.PR00.LPSS, PkgObj)
    External (_SB_.PR00.TPSS, PkgObj)
    External (_SB_.PR00.TSMC, PkgObj)
    External (_SB_.PR00.TSMF, PkgObj)
    External (_SB_.PR01, ProcessorObj)
    External (_SB_.PR02, ProcessorObj)
    External (_SB_.PR03, ProcessorObj)
    External (_SB_.PR04, ProcessorObj)
    External (_SB_.PR05, ProcessorObj)
    External (_SB_.PR06, ProcessorObj)
    External (_SB_.PR07, ProcessorObj)
    External (_SB_.PR08, ProcessorObj)
    External (_SB_.PR09, ProcessorObj)
    External (_SB_.PR10, ProcessorObj)
    External (_SB_.PR11, ProcessorObj)
    External (_SB_.PR12, ProcessorObj)
    External (_SB_.PR13, ProcessorObj)
    External (_SB_.PR14, ProcessorObj)
    External (_SB_.PR15, ProcessorObj)
    External (_SB_.PR16, ProcessorObj)
    External (_SB_.PR17, ProcessorObj)
    External (_SB_.PR18, ProcessorObj)
    External (_SB_.PR19, ProcessorObj)
    External (_SB_.PR20, ProcessorObj)
    External (_SB_.PR21, ProcessorObj)
    External (_SB_.PR22, ProcessorObj)
    External (_SB_.PR23, ProcessorObj)
    External (_SB_.PR24, ProcessorObj)
    External (_SB_.PR25, ProcessorObj)
    External (_SB_.PR26, ProcessorObj)
    External (_SB_.PR27, ProcessorObj)
    External (_SB_.PR28, ProcessorObj)
    External (_SB_.PR29, ProcessorObj)
    External (_SB_.PR30, ProcessorObj)
    External (_SB_.PR31, ProcessorObj)
    External (_SB_.SLPB, DeviceObj)
    External (_SB_.TAR0, FieldUnitObj)
    External (_SB_.TAR1, FieldUnitObj)
    External (_SB_.TAR2, FieldUnitObj)
    External (_TZ_.TZ00, ThermalZoneObj)
    External (ACTT, IntObj)
    External (ATPC, IntObj)
    External (BATR, IntObj)
    External (BMID, UnknownObj)
    External (CHGE, IntObj)
    External (CRTT, IntObj)
    External (DCFE, IntObj)
    External (DDDR, IntObj)
    External (DISP, MethodObj)    // 1 Arguments
    External (DPTF, IntObj)
    External (ECRD, IntObj)
    External (FND1, IntObj)
    External (FND2, IntObj)
    External (FND3, IntObj)
    External (HIDW, MethodObj)    // 4 Arguments
    External (HIWC, MethodObj)    // 1 Arguments
    External (IN34, IntObj)
    External (IPCS, MethodObj)    // 7 Arguments
    External (ODV0, IntObj)
    External (ODV1, IntObj)
    External (ODV2, IntObj)
    External (ODV3, IntObj)
    External (ODV4, IntObj)
    External (ODV5, IntObj)
    External (PCHE, FieldUnitObj)
    External (PF00, IntObj)
    External (PLID, IntObj)
    External (PNHM, IntObj)
    External (PPPR, IntObj)
    External (PPSZ, IntObj)
    External (PSVT, IntObj)
    External (PTPC, IntObj)
    External (PWRE, IntObj)
    External (PWRS, IntObj)
    External (S1AT, IntObj)
    External (S1CT, IntObj)
    External (S1DE, IntObj)
    External (S1HT, IntObj)
    External (S1PT, IntObj)
    External (S1S3, IntObj)
    External (S2DE, IntObj)
    External (S3DE, IntObj)
    External (S4DE, IntObj)
    External (S5DE, IntObj)
    External (S6DE, IntObj)
    External (S6P2, IntObj)
    External (SADE, IntObj)
    External (SSP1, IntObj)
    External (SSP2, IntObj)
    External (SSP3, IntObj)
    External (SSP4, IntObj)
    External (SSP5, IntObj)
    External (TCNT, IntObj)
    External (TSOD, IntObj)

    Scope (\_SB.PC00.LPCB.ECDV)
    {
        Method (DPST, 1, Serialized)
        {
            \_SB.PC00.LPCB.ECDV.ECW1 (0x32, Arg0)
            Local0 = \_SB.PC00.LPCB.ECDV.ECR1 (0x32)
            Return (Local0)
        }

        Method (DPRT, 0, NotSerialized)
        {
            Local0 = \_SB.PC00.LPCB.ECDV.ECR1 (0x32)
            Return (Local0)
        }

        Method (KDRT, 1, NotSerialized)
        {
            Local0 = EXRW (Arg0, 0x34, Zero, Zero)
            Return (Local0)
        }

        Method (DSTL, 2, NotSerialized)
        {
            EXRW (Arg0, 0x35, One, Arg1)
        }

        Method (DRTL, 1, NotSerialized)
        {
            Local0 = EXRW (Arg0, 0x35, Zero, Zero)
            Return (Local0)
        }

        Method (DSTH, 2, NotSerialized)
        {
            EXRW (Arg0, 0x36, One, Arg1)
        }

        Method (DRTH, 1, NotSerialized)
        {
            Local0 = EXRW (Arg0, 0x36, Zero, Zero)
            Return (Local0)
        }

        Method (DSHY, 2, NotSerialized)
        {
            EXRW (Arg0, 0x37, One, Arg1)
        }

        Method (DRHY, 1, NotSerialized)
        {
            Local0 = EXRW (Arg0, 0x37, Zero, Zero)
            Return (Local0)
        }

        Method (DSSQ, 1, NotSerialized)
        {
            \_SB.PC00.LPCB.ECDV.ECW1 (0x38, Arg0)
        }

        Method (DSRQ, 0, NotSerialized)
        {
            Local0 = \_SB.PC00.LPCB.ECDV.ECR1 (0x38)
            Return (Local0)
        }

        Method (EXRW, 4, Serialized)
        {
            \_SB.PC00.LPCB.ECDV.ECW1 (0x33, Arg0)
            If (Arg2)
            {
                \_SB.PC00.LPCB.ECDV.ECW1 (Arg1, Arg3)
            }
            Else
            {
                Local0 = \_SB.PC00.LPCB.ECDV.ECR1 (Arg1)
                Return (Local0)
            }
        }
    }

    Scope (\_SB)
    {
        Device (IETM)
        {
            Method (GHID, 1, Serialized)
            {
                If ((Arg0 == "IETM"))
                {
                    Return ("INTC1041")
                }

                If ((Arg0 == "SEN1"))
                {
                    Return ("INTC1046")
                }

                If ((Arg0 == "SEN2"))
                {
                    Return ("INTC1046")
                }

                If ((Arg0 == "SEN3"))
                {
                    Return ("INTC1046")
                }

                If ((Arg0 == "SEN4"))
                {
                    Return ("INTC1046")
                }

                If ((Arg0 == "SEN5"))
                {
                    Return ("INTC1046")
                }

                If ((Arg0 == "TPCH"))
                {
                    Return ("INTC1049")
                }

                If ((Arg0 == "TFN1"))
                {
                    Return ("INTC1048")
                }

                If ((Arg0 == "TFN2"))
                {
                    Return ("INTC1048")
                }

                If ((Arg0 == "TFN3"))
                {
                    Return ("INTC1048")
                }

                If ((Arg0 == "TPWR"))
                {
                    Return ("INTC1060")
                }

                If ((Arg0 == "1"))
                {
                    Return ("INTC1061")
                }

                If ((Arg0 == "CHRG"))
                {
                    Return ("INTC1046")
                }

                Return ("XXXX9999")
            }

            Name (_UID, "IETM")  // _UID: Unique ID
            Method (_HID, 0, NotSerialized)  // _HID: Hardware ID
            {
                Return (\_SB.IETM.GHID (_UID))
            }

            Method (_DSM, 4, Serialized)  // _DSM: Device-Specific Method
            {
                If (CondRefOf (HIWC))
                {
                    If (HIWC (Arg0))
                    {
                        If (CondRefOf (HIDW))
                        {
                            Return (HIDW (Arg0, Arg1, Arg2, Arg3))
                        }
                    }
                }

                Return (Buffer (One)
                {
                     0x00                                             // .
                })
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (((\DPTF == One) && (\IN34 == One)))
                {
                    If ((DDDR == One))
                    {
                        DISP ("EC_DPTF_STATE_ENABLE(1)\n")
                        \_SB.PC00.LPCB.ECDV.DPST (One)
                    }

                    DISP ("INTEL DPTF SUPPORTED\n")
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Name (PTRP, Zero)
            Name (PSEM, Zero)
            Name (ATRP, Zero)
            Name (ASEM, Zero)
            Name (YTRP, Zero)
            Name (YSEM, Zero)
            Method (_OSC, 4, Serialized)  // _OSC: Operating System Capabilities
            {
                CreateDWordField (Arg3, Zero, STS1)
                CreateDWordField (Arg3, 0x04, CAP1)
                If ((Arg1 != One))
                {
                    STS1 &= 0xFFFFFF00
                    STS1 |= 0x0A
                    Return (Arg3)
                }

                If ((Arg2 != 0x02))
                {
                    STS1 &= 0xFFFFFF00
                    STS1 |= 0x02
                    Return (Arg3)
                }

                If (CondRefOf (\_SB.APSV))
                {
                    If ((PSEM == Zero))
                    {
                        PSEM = One
                        PTRP = \_SB.APSV /* External reference */
                    }
                }

                If (CondRefOf (\_SB.AAC0))
                {
                    If ((ASEM == Zero))
                    {
                        ASEM = One
                        ATRP = \_SB.AAC0 /* External reference */
                    }
                }

                If (CondRefOf (\_SB.ACRT))
                {
                    If ((YSEM == Zero))
                    {
                        YSEM = One
                        YTRP = \_SB.ACRT /* External reference */
                    }
                }

                If ((Arg0 == ToUUID ("b23ba85d-c8b7-3542-88de-8de2ffcfd698") /* Unknown UUID */))
                {
                    DISP ("Intel(R) Dynamic Tuning Driver Installed\n")
                    If (~(STS1 & One))
                    {
                        If ((DDDR == Zero))
                        {
                            If ((CAP1 & 0x0F))
                            {
                                DISP ("EC_DPTF_STATE_ENABLE(0)\n")
                                \_SB.PC00.LPCB.ECDV.DPST (One)
                                DDDR = One
                            }
                        }

                        If ((CAP1 & One))
                        {
                            If ((CAP1 & 0x02))
                            {
                                \_SB.AAC0 = 0x6E
                            }
                            Else
                            {
                                \_SB.AAC0 = ATRP /* \_SB_.IETM.ATRP */
                            }

                            If ((CAP1 & 0x04))
                            {
                                \_SB.APSV = 0x6E
                            }
                            Else
                            {
                                \_SB.APSV = PTRP /* \_SB_.IETM.PTRP */
                            }

                            If ((CAP1 & 0x08))
                            {
                                \_SB.ACRT = 0xD2
                            }
                            Else
                            {
                                \_SB.ACRT = YTRP /* \_SB_.IETM.YTRP */
                            }

                            If (CondRefOf (\_TZ.TZ00))
                            {
                                Notify (\_TZ.TZ00, 0x81) // Information Change
                            }
                        }
                        Else
                        {
                            \_SB.ACRT = YTRP /* \_SB_.IETM.YTRP */
                            \_SB.APSV = PTRP /* \_SB_.IETM.PTRP */
                            \_SB.AAC0 = ATRP /* \_SB_.IETM.ATRP */
                        }

                        If (CondRefOf (\_TZ.TZ00))
                        {
                            Notify (\_TZ.TZ00, 0x81) // Information Change
                        }
                    }

                    Return (Arg3)
                }

                Return (Arg3)
            }

            Method (DCFG, 0, NotSerialized)
            {
                Return (\DCFE) /* External reference */
            }

            Name (ODVX, Package (0x06)
            {
                Zero, 
                Zero, 
                Zero, 
                Zero, 
                Zero, 
                Zero
            })
            Method (ODVP, 0, Serialized)
            {
                ODVX [Zero] = \ODV0 /* External reference */
                ODVX [One] = \ODV1 /* External reference */
                ODVX [0x02] = \ODV2 /* External reference */
                ODVX [0x03] = \ODV3 /* External reference */
                ODVX [0x04] = \ODV4 /* External reference */
                ODVX [0x05] = \ODV5 /* External reference */
                Return (ODVX) /* \_SB_.IETM.ODVX */
            }
        }
    }

    Scope (\_SB.PC00.LPCB.ECDV)
    {
        Mutex (PATM, 0x00)
        Name (SNUM, Zero)
        Method (DPNT, 0, NotSerialized)
        {
            DISP ("DPNT Called\n")
            If ((\_SB.PC00.LPCB.ECDV.DPRT () == One))
            {
                Local0 = \_SB.PC00.LPCB.ECDV.DSRQ ()
                While (Local0)
                {
                    DISP (" Trigger Sensors (")
                    DISP (Local0)
                    DISP (")\n")
                    \_SB.PC00.LPCB.ECDV.DSSQ (0xFF)
                    Local1 = Zero
                    If (Local1 = (Local0 & 0x80)){}
                    If (Local1 = (Local0 & 0x40)){}
                    If (Local1 = (Local0 & 0x20))
                    {
                        Notify (\_SB.PC00.LPCB.ECDV.AMBF, 0x90) // Device-Specific
                    }

                    If (Local1 = (Local0 & 0x10))
                    {
                        Notify (\_SB.PC00.LPCB.ECDV.TMEM, 0x90) // Device-Specific
                    }

                    If (Local1 = (Local0 & 0x08))
                    {
                        Notify (\_SB.PC00.LPCB.ECDV.CHRG, 0x90) // Device-Specific
                    }

                    If (Local1 = (Local0 & 0x04))
                    {
                        Notify (\_SB.PC00.LPCB.ECDV.NGFF, 0x90) // Device-Specific
                    }

                    If (Local1 = (Local0 & 0x02))
                    {
                        Notify (\_SB.PC00.LPCB.ECDV.TSKN, 0x90) // Device-Specific
                    }

                    If (Local1 = (Local0 & One))
                    {
                        Notify (\_SB.PC00.TCPU, 0x90) // Device-Specific
                    }

                    Local0 = \_SB.PC00.LPCB.ECDV.DSRQ ()
                }
            }
        }
    }

    Scope (\_SB.IETM)
    {
        Method (KTOC, 1, Serialized)
        {
            If ((Arg0 > 0x0AAC))
            {
                Return (((Arg0 - 0x0AAC) / 0x0A))
            }
            Else
            {
                Return (Zero)
            }
        }

        Method (CTOK, 1, Serialized)
        {
            Return (((Arg0 * 0x0A) + 0x0AAC))
        }

        Method (C10K, 1, Serialized)
        {
            Name (TMP1, Buffer (0x10)
            {
                 0x00                                             // .
            })
            CreateByteField (TMP1, Zero, TMPL)
            CreateByteField (TMP1, One, TMPH)
            Local0 = (Arg0 + 0x0AAC)
            TMPL = (Local0 & 0xFF)
            TMPH = ((Local0 & 0xFF00) >> 0x08)
            ToInteger (TMP1, Local1)
            Return (Local1)
        }

        Method (K10C, 1, Serialized)
        {
            If ((Arg0 > 0x0AAC))
            {
                Return ((Arg0 - 0x0AAC))
            }
            Else
            {
                Return (Zero)
            }
        }
    }

    Scope (\_SB.PC00.TCPU)
    {
        Name (PFLG, Zero)
        Method (_STA, 0, NotSerialized)  // _STA: Status
        {
            If ((\SADE == One))
            {
                Return (0x0F)
            }
            Else
            {
                Return (Zero)
            }
        }

        OperationRegion (CPWR, SystemMemory, ((\_SB.PC00.MC.MHBR << 0x0F) + 0x5000), 0x1000)
        Field (CPWR, ByteAcc, NoLock, Preserve)
        {
            Offset (0x930), 
            PTDP,   15, 
            Offset (0x932), 
            PMIN,   15, 
            Offset (0x934), 
            PMAX,   15, 
            Offset (0x936), 
            TMAX,   7, 
            Offset (0x938), 
            PWRU,   4, 
            Offset (0x939), 
            EGYU,   5, 
            Offset (0x93A), 
            TIMU,   4, 
            Offset (0x958), 
            Offset (0x95C), 
            LPMS,   1, 
            CTNL,   2, 
            Offset (0x978), 
            PCTP,   8, 
            Offset (0x998), 
            RP0C,   8, 
            RP1C,   8, 
            RPNC,   8, 
            Offset (0xF3C), 
            TRAT,   8, 
            Offset (0xF40), 
            PTD1,   15, 
            Offset (0xF42), 
            TRA1,   8, 
            Offset (0xF44), 
            PMX1,   15, 
            Offset (0xF46), 
            PMN1,   15, 
            Offset (0xF48), 
            PTD2,   15, 
            Offset (0xF4A), 
            TRA2,   8, 
            Offset (0xF4C), 
            PMX2,   15, 
            Offset (0xF4E), 
            PMN2,   15, 
            Offset (0xF50), 
            CTCL,   2, 
                ,   29, 
            CLCK,   1, 
            MNTR,   8
        }

        Name (XPCC, Zero)
        Method (PPCC, 0, Serialized)
        {
            Return (NPCC) /* \_SB_.PC00.TCPU.NPCC */
        }

        Name (NPCC, Package (0x03)
        {
            0x02, 
            Package (0x06)
            {
                Zero, 
                0x88B8, 
                0xAFC8, 
                0x6D60, 
                0x7D00, 
                0x03E8
            }, 

            Package (0x06)
            {
                One, 
                0xDBBA, 
                0xDBBA, 
                Zero, 
                Zero, 
                0x03E8
            }
        })
        Method (CPNU, 2, Serialized)
        {
            Name (CNVT, Zero)
            Name (PPUU, Zero)
            Name (RMDR, Zero)
            If ((PWRU == Zero))
            {
                PPUU = One
            }
            Else
            {
                PPUU = (PWRU-- << 0x02)
            }

            Divide (Arg0, PPUU, RMDR, CNVT) /* \_SB_.PC00.TCPU.CPNU.CNVT */
            If ((Arg1 == Zero))
            {
                Return (CNVT) /* \_SB_.PC00.TCPU.CPNU.CNVT */
            }
            Else
            {
                CNVT *= 0x03E8
                RMDR *= 0x03E8
                RMDR /= PPUU
                CNVT += RMDR /* \_SB_.PC00.TCPU.CPNU.RMDR */
                Return (CNVT) /* \_SB_.PC00.TCPU.CPNU.CNVT */
            }
        }

        Method (CPL0, 0, NotSerialized)
        {
        }

        Method (CPL1, 0, NotSerialized)
        {
        }

        Method (CPL2, 0, NotSerialized)
        {
        }

        Name (LSTM, Zero)
        Name (_PPC, Zero)  // _PPC: Performance Present Capabilities
        Method (SPPC, 1, Serialized)
        {
            If (CondRefOf (\_SB.CPPC))
            {
                \_SB.CPPC = Arg0
            }

            If ((ToInteger (\TCNT) > Zero))
            {
                Notify (\_SB.PR00, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > One))
            {
                Notify (\_SB.PR01, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x02))
            {
                Notify (\_SB.PR02, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x03))
            {
                Notify (\_SB.PR03, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x04))
            {
                Notify (\_SB.PR04, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x05))
            {
                Notify (\_SB.PR05, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x06))
            {
                Notify (\_SB.PR06, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x07))
            {
                Notify (\_SB.PR07, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x08))
            {
                Notify (\_SB.PR08, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x09))
            {
                Notify (\_SB.PR09, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x0A))
            {
                Notify (\_SB.PR10, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x0B))
            {
                Notify (\_SB.PR11, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x0C))
            {
                Notify (\_SB.PR12, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x0D))
            {
                Notify (\_SB.PR13, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x0E))
            {
                Notify (\_SB.PR14, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x0F))
            {
                Notify (\_SB.PR15, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x10))
            {
                Notify (\_SB.PR16, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x11))
            {
                Notify (\_SB.PR17, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x12))
            {
                Notify (\_SB.PR18, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x13))
            {
                Notify (\_SB.PR19, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x14))
            {
                Notify (\_SB.PR20, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x15))
            {
                Notify (\_SB.PR21, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x16))
            {
                Notify (\_SB.PR22, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x17))
            {
                Notify (\_SB.PR23, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x18))
            {
                Notify (\_SB.PR24, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x19))
            {
                Notify (\_SB.PR25, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x1A))
            {
                Notify (\_SB.PR26, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x1B))
            {
                Notify (\_SB.PR27, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x1C))
            {
                Notify (\_SB.PR28, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x1D))
            {
                Notify (\_SB.PR29, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x1E))
            {
                Notify (\_SB.PR30, 0x80) // Status Change
            }

            If ((ToInteger (\TCNT) > 0x1F))
            {
                Notify (\_SB.PR31, 0x80) // Status Change
            }
        }

        Method (SPUR, 1, NotSerialized)
        {
            If ((Arg0 <= \TCNT))
            {
                If ((\_SB.PAGD._STA () == 0x0F))
                {
                    \_SB.PAGD._PUR [One] = Arg0
                    Notify (\_SB.PAGD, 0x80) // Status Change
                }
            }
        }

        Method (PCCC, 0, Serialized)
        {
            PCCX [Zero] = One
            Switch (ToInteger (CPNU (PTDP, Zero)))
            {
                Case (0x39)
                {
                    DerefOf (PCCX [One]) [Zero] = 0xA7F8
                    DerefOf (PCCX [One]) [One] = 0x00017318
                }
                Case (0x2F)
                {
                    DerefOf (PCCX [One]) [Zero] = 0x9858
                    DerefOf (PCCX [One]) [One] = 0x00014C08
                }
                Case (0x25)
                {
                    DerefOf (PCCX [One]) [Zero] = 0x7148
                    DerefOf (PCCX [One]) [One] = 0xD6D8
                }
                Case (0x19)
                {
                    DerefOf (PCCX [One]) [Zero] = 0x3E80
                    DerefOf (PCCX [One]) [One] = 0x7D00
                }
                Case (0x0F)
                {
                    DerefOf (PCCX [One]) [Zero] = 0x36B0
                    DerefOf (PCCX [One]) [One] = 0x7D00
                }
                Case (0x0B)
                {
                    DerefOf (PCCX [One]) [Zero] = 0x36B0
                    DerefOf (PCCX [One]) [One] = 0x61A8
                }
                Default
                {
                    DerefOf (PCCX [One]) [Zero] = 0xFF
                    DerefOf (PCCX [One]) [One] = 0xFF
                }

            }

            Return (PCCX) /* \_SB_.PC00.TCPU.PCCX */
        }

        Name (PCCX, Package (0x02)
        {
            0x80000000, 
            Package (0x02)
            {
                0x80000000, 
                0x80000000
            }
        })
        Name (KEFF, Package (0x1E)
        {
            Package (0x02)
            {
                0x01BC, 
                Zero
            }, 

            Package (0x02)
            {
                0x01CF, 
                0x27
            }, 

            Package (0x02)
            {
                0x01E1, 
                0x4B
            }, 

            Package (0x02)
            {
                0x01F3, 
                0x6C
            }, 

            Package (0x02)
            {
                0x0206, 
                0x8B
            }, 

            Package (0x02)
            {
                0x0218, 
                0xA8
            }, 

            Package (0x02)
            {
                0x022A, 
                0xC3
            }, 

            Package (0x02)
            {
                0x023D, 
                0xDD
            }, 

            Package (0x02)
            {
                0x024F, 
                0xF4
            }, 

            Package (0x02)
            {
                0x0261, 
                0x010B
            }, 

            Package (0x02)
            {
                0x0274, 
                0x011F
            }, 

            Package (0x02)
            {
                0x032C, 
                0x01BD
            }, 

            Package (0x02)
            {
                0x03D7, 
                0x0227
            }, 

            Package (0x02)
            {
                0x048B, 
                0x026D
            }, 

            Package (0x02)
            {
                0x053E, 
                0x02A1
            }, 

            Package (0x02)
            {
                0x05F7, 
                0x02C6
            }, 

            Package (0x02)
            {
                0x06A8, 
                0x02E6
            }, 

            Package (0x02)
            {
                0x075D, 
                0x02FF
            }, 

            Package (0x02)
            {
                0x0818, 
                0x0311
            }, 

            Package (0x02)
            {
                0x08CF, 
                0x0322
            }, 

            Package (0x02)
            {
                0x179C, 
                0x0381
            }, 

            Package (0x02)
            {
                0x2DDC, 
                0x039C
            }, 

            Package (0x02)
            {
                0x44A8, 
                0x039E
            }, 

            Package (0x02)
            {
                0x5C35, 
                0x0397
            }, 

            Package (0x02)
            {
                0x747D, 
                0x038D
            }, 

            Package (0x02)
            {
                0x8D7F, 
                0x0382
            }, 

            Package (0x02)
            {
                0xA768, 
                0x0376
            }, 

            Package (0x02)
            {
                0xC23B, 
                0x0369
            }, 

            Package (0x02)
            {
                0xDE26, 
                0x035A
            }, 

            Package (0x02)
            {
                0xFB7C, 
                0x034A
            }
        })
        Name (CEUP, Package (0x06)
        {
            0x80000000, 
            0x80000000, 
            0x80000000, 
            0x80000000, 
            0x80000000, 
            0x80000000
        })
        Method (_TMP, 0, Serialized)  // _TMP: Temperature
        {
            If (\ECRD)
            {
                Local0 = \_SB.PC00.LPCB.ECDV.KDRT (Zero)
                Return ((0x0AAC + (Local0 * 0x0A)))
            }
            Else
            {
                Return (0x0BB8)
            }
        }

        Method (_DTI, 1, NotSerialized)  // _DTI: Device Temperature Indication
        {
            LSTM = Arg0
            Notify (\_SB.PC00.TCPU, 0x91) // Device-Specific
        }

        Method (_NTT, 0, NotSerialized)  // _NTT: Notification Temperature Threshold
        {
            Return (0x0ADE)
        }

        Name (PTYP, Zero)
        Method (_PSS, 0, NotSerialized)  // _PSS: Performance Supported States
        {
            If (CondRefOf (\_SB.PR00._PSS))
            {
                Return (\_SB.PR00._PSS ())
            }
            Else
            {
                Return (Package (0x02)
                {
                    Package (0x06)
                    {
                        Zero, 
                        Zero, 
                        Zero, 
                        Zero, 
                        Zero, 
                        Zero
                    }, 

                    Package (0x06)
                    {
                        Zero, 
                        Zero, 
                        Zero, 
                        Zero, 
                        Zero, 
                        Zero
                    }
                })
            }
        }

        Method (_TSS, 0, NotSerialized)  // _TSS: Throttling Supported States
        {
            If (CondRefOf (\_SB.PR00._TSS))
            {
                Return (\_SB.PR00._TSS ())
            }
            Else
            {
                Return (Package (0x01)
                {
                    Package (0x05)
                    {
                        One, 
                        Zero, 
                        Zero, 
                        Zero, 
                        Zero
                    }
                })
            }
        }

        Method (_TPC, 0, NotSerialized)  // _TPC: Throttling Present Capabilities
        {
            If (CondRefOf (\_SB.PR00._TPC))
            {
                Return (\_SB.PR00._TPC) /* External reference */
            }
            Else
            {
                Return (Zero)
            }
        }

        Method (_PTC, 0, NotSerialized)  // _PTC: Processor Throttling Control
        {
            If ((CondRefOf (\PF00) && (\PF00 != 0x80000000)))
            {
                If ((\PF00 & 0x04))
                {
                    Return (Package (0x02)
                    {
                        Buffer (0x11)
                        {
                            /* 0000 */  0x82, 0x0C, 0x00, 0x7F, 0x00, 0x00, 0x00, 0x00,  // ........
                            /* 0008 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x79,  // .......y
                            /* 0010 */  0x00                                             // .
                        }, 

                        Buffer (0x11)
                        {
                            /* 0000 */  0x82, 0x0C, 0x00, 0x7F, 0x00, 0x00, 0x00, 0x00,  // ........
                            /* 0008 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x79,  // .......y
                            /* 0010 */  0x00                                             // .
                        }
                    })
                }
                Else
                {
                    Return (Package (0x02)
                    {
                        Buffer (0x11)
                        {
                            /* 0000 */  0x82, 0x0C, 0x00, 0x01, 0x05, 0x00, 0x00, 0x10,  // ........
                            /* 0008 */  0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x79,  // .......y
                            /* 0010 */  0x00                                             // .
                        }, 

                        Buffer (0x11)
                        {
                            /* 0000 */  0x82, 0x0C, 0x00, 0x01, 0x05, 0x00, 0x00, 0x10,  // ........
                            /* 0008 */  0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x79,  // .......y
                            /* 0010 */  0x00                                             // .
                        }
                    })
                }
            }
            Else
            {
                Return (Package (0x02)
                {
                    Buffer (0x11)
                    {
                        /* 0000 */  0x82, 0x0C, 0x00, 0x7F, 0x00, 0x00, 0x00, 0x00,  // ........
                        /* 0008 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x79,  // .......y
                        /* 0010 */  0x00                                             // .
                    }, 

                    Buffer (0x11)
                    {
                        /* 0000 */  0x82, 0x0C, 0x00, 0x7F, 0x00, 0x00, 0x00, 0x00,  // ........
                        /* 0008 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x79,  // .......y
                        /* 0010 */  0x00                                             // .
                    }
                })
            }
        }

        Method (_TSD, 0, NotSerialized)  // _TSD: Throttling State Dependencies
        {
            If (CondRefOf (\_SB.PR00._TSD))
            {
                Return (\_SB.PR00._TSD ())
            }
            Else
            {
                Return (Package (0x01)
                {
                    Package (0x05)
                    {
                        0x05, 
                        Zero, 
                        Zero, 
                        0xFC, 
                        Zero
                    }
                })
            }
        }

        Method (_TDL, 0, NotSerialized)  // _TDL: T-State Depth Limit
        {
            If ((CondRefOf (\_SB.PR00._TSS) && CondRefOf (\_SB.CFGD)))
            {
                If ((\_SB.CFGD & 0x2000))
                {
                    Return ((SizeOf (\_SB.PR00.TSMF) - One))
                }
                Else
                {
                    Return ((SizeOf (\_SB.PR00.TSMC) - One))
                }
            }
            Else
            {
                Return (Zero)
            }
        }

        Method (_PDL, 0, NotSerialized)  // _PDL: P-state Depth Limit
        {
            If (CondRefOf (\_SB.PR00._PSS))
            {
                If ((\_SB.OSCP & 0x0400))
                {
                    Return ((SizeOf (\_SB.PR00.TPSS) - One))
                }
                Else
                {
                    Return ((SizeOf (\_SB.PR00.LPSS) - One))
                }
            }
            Else
            {
                Return (Zero)
            }
        }

        Name (TJMX, 0x6E)
        Method (_TSP, 0, Serialized)  // _TSP: Thermal Sampling Period
        {
            Return (Zero)
        }

        Method (_AC0, 0, Serialized)  // _ACx: Active Cooling, x=0-9
        {
            Local1 = \_SB.IETM.CTOK (TJMX)
            Local1 -= 0x0A
            If ((LSTM >= Local1))
            {
                Return ((Local1 - 0x14))
            }
            Else
            {
                Return (Local1)
            }
        }

        Method (_AC1, 0, Serialized)  // _ACx: Active Cooling, x=0-9
        {
            Local1 = \_SB.IETM.CTOK (TJMX)
            Local1 -= 0x1E
            If ((LSTM >= Local1))
            {
                Return ((Local1 - 0x14))
            }
            Else
            {
                Return (Local1)
            }
        }

        Method (_AC2, 0, Serialized)  // _ACx: Active Cooling, x=0-9
        {
            Local1 = \_SB.IETM.CTOK (TJMX)
            Local1 -= 0x28
            If ((LSTM >= Local1))
            {
                Return ((Local1 - 0x14))
            }
            Else
            {
                Return (Local1)
            }
        }

        Method (_AC3, 0, Serialized)  // _ACx: Active Cooling, x=0-9
        {
            Local1 = \_SB.IETM.CTOK (TJMX)
            Local1 -= 0x37
            If ((LSTM >= Local1))
            {
                Return ((Local1 - 0x14))
            }
            Else
            {
                Return (Local1)
            }
        }

        Method (_AC4, 0, Serialized)  // _ACx: Active Cooling, x=0-9
        {
            Local1 = \_SB.IETM.CTOK (TJMX)
            Local1 -= 0x46
            If ((LSTM >= Local1))
            {
                Return ((Local1 - 0x14))
            }
            Else
            {
                Return (Local1)
            }
        }

        Method (_PSV, 0, Serialized)  // _PSV: Passive Temperature
        {
            Return (\_SB.IETM.CTOK (TJMX))
        }

        Method (_CRT, 0, Serialized)  // _CRT: Critical Temperature
        {
            Return (\_SB.IETM.CTOK (TJMX))
        }

        Method (_CR3, 0, Serialized)  // _CR3: Warm/Standby Temperature
        {
            Return (\_SB.IETM.CTOK (TJMX))
        }

        Method (_HOT, 0, Serialized)  // _HOT: Hot Temperature
        {
            Return (\_SB.IETM.CTOK (TJMX))
        }

        Method (UVTH, 1, Serialized)
        {
        }
    }

    Scope (\_SB.IETM)
    {
        Name (CTSP, Package (0x01)
        {
            ToUUID ("e145970a-e4c1-4d73-900e-c9c5a69dd067") /* Unknown UUID */
        })
    }

    Scope (\_SB.PC00.TCPU)
    {
        Method (TDPL, 0, Serialized)
        {
            Name (AAAA, Zero)
            Name (BBBB, Zero)
            Name (CCCC, Zero)
            Local0 = CTNL /* \_SB_.PC00.TCPU.CTNL */
            If (((Local0 == One) || (Local0 == 0x02)))
            {
                Local0 = \_SB.CLVL /* External reference */
            }
            Else
            {
                Return (Package (0x01)
                {
                    Zero
                })
            }

            If ((CLCK == One))
            {
                Local0 = One
            }

            AAAA = CPNU (\_SB.PL10, One)
            BBBB = CPNU (\_SB.PL11, One)
            CCCC = CPNU (\_SB.PL12, One)
            Name (TMP1, Package (0x01)
            {
                Package (0x05)
                {
                    0x80000000, 
                    0x80000000, 
                    0x80000000, 
                    0x80000000, 
                    0x80000000
                }
            })
            Name (TMP2, Package (0x02)
            {
                Package (0x05)
                {
                    0x80000000, 
                    0x80000000, 
                    0x80000000, 
                    0x80000000, 
                    0x80000000
                }, 

                Package (0x05)
                {
                    0x80000000, 
                    0x80000000, 
                    0x80000000, 
                    0x80000000, 
                    0x80000000
                }
            })
            Name (TMP3, Package (0x03)
            {
                Package (0x05)
                {
                    0x80000000, 
                    0x80000000, 
                    0x80000000, 
                    0x80000000, 
                    0x80000000
                }, 

                Package (0x05)
                {
                    0x80000000, 
                    0x80000000, 
                    0x80000000, 
                    0x80000000, 
                    0x80000000
                }, 

                Package (0x05)
                {
                    0x80000000, 
                    0x80000000, 
                    0x80000000, 
                    0x80000000, 
                    0x80000000
                }
            })
            If ((Local0 == 0x03))
            {
                If ((AAAA > BBBB))
                {
                    If ((AAAA > CCCC))
                    {
                        If ((BBBB > CCCC))
                        {
                            Local3 = Zero
                            LEV0 = Zero
                            Local4 = One
                            LEV1 = One
                            Local5 = 0x02
                            LEV2 = 0x02
                        }
                        Else
                        {
                            Local3 = Zero
                            LEV0 = Zero
                            Local5 = One
                            LEV1 = 0x02
                            Local4 = 0x02
                            LEV2 = One
                        }
                    }
                    Else
                    {
                        Local5 = Zero
                        LEV0 = 0x02
                        Local3 = One
                        LEV1 = Zero
                        Local4 = 0x02
                        LEV2 = One
                    }
                }
                ElseIf ((BBBB > CCCC))
                {
                    If ((AAAA > CCCC))
                    {
                        Local4 = Zero
                        LEV0 = One
                        Local3 = One
                        LEV1 = Zero
                        Local5 = 0x02
                        LEV2 = 0x02
                    }
                    Else
                    {
                        Local4 = Zero
                        LEV0 = One
                        Local5 = One
                        LEV1 = 0x02
                        Local3 = 0x02
                        LEV2 = Zero
                    }
                }
                Else
                {
                    Local5 = Zero
                    LEV0 = 0x02
                    Local4 = One
                    LEV1 = One
                    Local3 = 0x02
                    LEV2 = Zero
                }

                Local1 = (\_SB.TAR0 + One)
                Local2 = (Local1 * 0x64)
                DerefOf (TMP3 [Local3]) [Zero] = AAAA /* \_SB_.PC00.TCPU.TDPL.AAAA */
                DerefOf (TMP3 [Local3]) [One] = Local2
                DerefOf (TMP3 [Local3]) [0x02] = \_SB.CTC0 /* External reference */
                DerefOf (TMP3 [Local3]) [0x03] = Local1
                DerefOf (TMP3 [Local3]) [0x04] = Zero
                Local1 = (\_SB.TAR1 + One)
                Local2 = (Local1 * 0x64)
                DerefOf (TMP3 [Local4]) [Zero] = BBBB /* \_SB_.PC00.TCPU.TDPL.BBBB */
                DerefOf (TMP3 [Local4]) [One] = Local2
                DerefOf (TMP3 [Local4]) [0x02] = \_SB.CTC1 /* External reference */
                DerefOf (TMP3 [Local4]) [0x03] = Local1
                DerefOf (TMP3 [Local4]) [0x04] = Zero
                Local1 = (\_SB.TAR2 + One)
                Local2 = (Local1 * 0x64)
                DerefOf (TMP3 [Local5]) [Zero] = CCCC /* \_SB_.PC00.TCPU.TDPL.CCCC */
                DerefOf (TMP3 [Local5]) [One] = Local2
                DerefOf (TMP3 [Local5]) [0x02] = \_SB.CTC2 /* External reference */
                DerefOf (TMP3 [Local5]) [0x03] = Local1
                DerefOf (TMP3 [Local5]) [0x04] = Zero
                Return (TMP3) /* \_SB_.PC00.TCPU.TDPL.TMP3 */
            }

            If ((Local0 == 0x02))
            {
                If ((AAAA > BBBB))
                {
                    Local3 = Zero
                    Local4 = One
                    LEV0 = Zero
                    LEV1 = One
                    LEV2 = Zero
                }
                Else
                {
                    Local4 = Zero
                    Local3 = One
                    LEV0 = One
                    LEV1 = Zero
                    LEV2 = Zero
                }

                Local1 = (\_SB.TAR0 + One)
                Local2 = (Local1 * 0x64)
                DerefOf (TMP2 [Local3]) [Zero] = AAAA /* \_SB_.PC00.TCPU.TDPL.AAAA */
                DerefOf (TMP2 [Local3]) [One] = Local2
                DerefOf (TMP2 [Local3]) [0x02] = \_SB.CTC0 /* External reference */
                DerefOf (TMP2 [Local3]) [0x03] = Local1
                DerefOf (TMP2 [Local3]) [0x04] = Zero
                Local1 = (\_SB.TAR1 + One)
                Local2 = (Local1 * 0x64)
                DerefOf (TMP2 [Local4]) [Zero] = BBBB /* \_SB_.PC00.TCPU.TDPL.BBBB */
                DerefOf (TMP2 [Local4]) [One] = Local2
                DerefOf (TMP2 [Local4]) [0x02] = \_SB.CTC1 /* External reference */
                DerefOf (TMP2 [Local4]) [0x03] = Local1
                DerefOf (TMP2 [Local4]) [0x04] = Zero
                Return (TMP2) /* \_SB_.PC00.TCPU.TDPL.TMP2 */
            }

            If ((Local0 == One))
            {
                Switch (ToInteger (\_SB.CBMI))
                {
                    Case (Zero)
                    {
                        Local1 = (\_SB.TAR0 + One)
                        Local2 = (Local1 * 0x64)
                        DerefOf (TMP1 [Zero]) [Zero] = AAAA /* \_SB_.PC00.TCPU.TDPL.AAAA */
                        DerefOf (TMP1 [Zero]) [One] = Local2
                        DerefOf (TMP1 [Zero]) [0x02] = \_SB.CTC0 /* External reference */
                        DerefOf (TMP1 [Zero]) [0x03] = Local1
                        DerefOf (TMP1 [Zero]) [0x04] = Zero
                        LEV0 = Zero
                        LEV1 = Zero
                        LEV2 = Zero
                    }
                    Case (One)
                    {
                        Local1 = (\_SB.TAR1 + One)
                        Local2 = (Local1 * 0x64)
                        DerefOf (TMP1 [Zero]) [Zero] = BBBB /* \_SB_.PC00.TCPU.TDPL.BBBB */
                        DerefOf (TMP1 [Zero]) [One] = Local2
                        DerefOf (TMP1 [Zero]) [0x02] = \_SB.CTC1 /* External reference */
                        DerefOf (TMP1 [Zero]) [0x03] = Local1
                        DerefOf (TMP1 [Zero]) [0x04] = Zero
                        LEV0 = One
                        LEV1 = One
                        LEV2 = One
                    }
                    Case (0x02)
                    {
                        Local1 = (\_SB.TAR2 + One)
                        Local2 = (Local1 * 0x64)
                        DerefOf (TMP1 [Zero]) [Zero] = CCCC /* \_SB_.PC00.TCPU.TDPL.CCCC */
                        DerefOf (TMP1 [Zero]) [One] = Local2
                        DerefOf (TMP1 [Zero]) [0x02] = \_SB.CTC2 /* External reference */
                        DerefOf (TMP1 [Zero]) [0x03] = Local1
                        DerefOf (TMP1 [Zero]) [0x04] = Zero
                        LEV0 = 0x02
                        LEV1 = 0x02
                        LEV2 = 0x02
                    }

                }

                Return (TMP1) /* \_SB_.PC00.TCPU.TDPL.TMP1 */
            }

            Return (Zero)
        }

        Name (MAXT, Zero)
        Method (TDPC, 0, NotSerialized)
        {
            Return (MAXT) /* \_SB_.PC00.TCPU.MAXT */
        }

        Name (LEV0, Zero)
        Name (LEV1, Zero)
        Name (LEV2, Zero)
        Method (STDP, 1, Serialized)
        {
            If ((Arg0 >= \_SB.CLVL))
            {
                Return (Zero)
            }

            Switch (ToInteger (Arg0))
            {
                Case (Zero)
                {
                    Local0 = LEV0 /* \_SB_.PC00.TCPU.LEV0 */
                }
                Case (One)
                {
                    Local0 = LEV1 /* \_SB_.PC00.TCPU.LEV1 */
                }
                Case (0x02)
                {
                    Local0 = LEV2 /* \_SB_.PC00.TCPU.LEV2 */
                }

            }

            Switch (ToInteger (Local0))
            {
                Case (Zero)
                {
                    CPL0 ()
                }
                Case (One)
                {
                    CPL1 ()
                }
                Case (0x02)
                {
                    CPL2 ()
                }

            }

            Notify (\_SB.PC00.TCPU, 0x83) // Device-Specific Change
        }
    }

    Scope (\_SB.IETM)
    {
        Method (TEVT, 2, Serialized)
        {
            Switch (ToInteger (Arg0))
            {
                Case ("IETM")
                {
                    Notify (\_SB.IETM, Arg1)
                }
                Case ("TCPU")
                {
                    Notify (\_SB.PC00.TCPU, Arg1)
                }
                Case ("TPCH")
                {
                    Notify (\_SB.TPCH, Arg1)
                }

            }
        }
    }

    Scope (\_SB)
    {
        Device (TPCH)
        {
            Name (_UID, "TPCH")  // _UID: Unique ID
            Method (_HID, 0, NotSerialized)  // _HID: Hardware ID
            {
                Return (\_SB.IETM.GHID (_UID))
            }

            Name (_STR, Unicode ("Intel PCH FIVR Participant"))  // _STR: Description String
            Name (PTYP, 0x05)
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((\PCHE == One))
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (RFC0, 1, Serialized)
            {
                IPCS (0xA3, One, 0x08, Zero, Arg0, Zero, Zero)
                Return (Package (0x01)
                {
                    Zero
                })
            }

            Method (RFC1, 1, Serialized)
            {
                IPCS (0xA3, One, 0x08, One, Arg0, Zero, Zero)
                Return (Package (0x01)
                {
                    Zero
                })
            }

            Method (SEMI, 1, Serialized)
            {
                IPCS (0xA3, One, 0x08, 0x02, Arg0, Zero, Zero)
                Return (Package (0x01)
                {
                    Zero
                })
            }

            Method (PKGC, 1, Serialized)
            {
                Name (PPKG, Package (0x02)
                {
                    Zero, 
                    Zero
                })
                PPKG [Zero] = DerefOf (Arg0 [Zero])
                PPKG [One] = DerefOf (Arg0 [One])
                Return (PPKG) /* \_SB_.TPCH.PKGC.PPKG */
            }

            Method (GFC0, 0, Serialized)
            {
                Local0 = IPCS (0xA3, Zero, 0x08, Zero, Zero, Zero, Zero)
                Local1 = \_SB.TPCH.PKGC (Local0)
                Return (Local1)
            }

            Method (GFC1, 0, Serialized)
            {
                Local0 = IPCS (0xA3, Zero, 0x08, One, Zero, Zero, Zero)
                Local1 = \_SB.TPCH.PKGC (Local0)
                Return (Local1)
            }

            Method (GEMI, 0, Serialized)
            {
                Local0 = IPCS (0xA3, Zero, 0x08, 0x02, Zero, Zero, Zero)
                Local1 = \_SB.TPCH.PKGC (Local0)
                Return (Local1)
            }

            Method (GFFS, 0, Serialized)
            {
                Local0 = IPCS (0xA3, Zero, 0x08, 0x03, Zero, Zero, Zero)
                Local1 = \_SB.TPCH.PKGC (Local0)
                Return (Local1)
            }

            Method (GFCS, 0, Serialized)
            {
                Local0 = IPCS (0xA3, Zero, 0x08, 0x04, Zero, Zero, Zero)
                Local1 = \_SB.TPCH.PKGC (Local0)
                Return (Local1)
            }
        }
    }

    Scope (\_SB.PC00.LPCB.ECDV)
    {
        Device (NGFF)
        {
            Name (_HID, "INTC1046")  // _HID: Hardware ID
            Name (_UID, "NGFF")  // _UID: Unique ID
            Name (_STR, Unicode ("NGFF Temperature Sensor (HT3)"))  // _STR: Description String
            Name (PTYP, 0x03)
            Name (CTYP, Zero)
            Name (PFLG, Zero)
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((\S2DE == One))
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_TMP, 0, Serialized)  // _TMP: Temperature
            {
                If (\ECRD)
                {
                    Local0 = \_SB.PC00.LPCB.ECDV.KDRT (0x02)
                    Return ((0x0AAC + (Local0 * 0x0A)))
                }
                Else
                {
                    Return (0x0BB8)
                }
            }

            Name (PATC, 0x02)
            Method (PAT0, 1, Serialized)
            {
                If (\ECRD)
                {
                    Local0 = Acquire (\_SB.PC00.LPCB.ECDV.PATM, 0x0064)
                    If ((Local0 == Zero))
                    {
                        Local1 = \_SB.IETM.KTOC (Arg0)
                        \_SB.PC00.LPCB.ECDV.DSHY (0x02, 0x02)
                        \_SB.PC00.LPCB.ECDV.DSTL (0x02, Local1)
                        Release (\_SB.PC00.LPCB.ECDV.PATM)
                    }
                }
            }

            Method (PAT1, 1, Serialized)
            {
                If (\ECRD)
                {
                    Local0 = Acquire (\_SB.PC00.LPCB.ECDV.PATM, 0x0064)
                    If ((Local0 == Zero))
                    {
                        Local1 = \_SB.IETM.KTOC (Arg0)
                        \_SB.PC00.LPCB.ECDV.DSHY (0x02, 0x02)
                        \_SB.PC00.LPCB.ECDV.DSTH (0x02, Local1)
                        Release (\_SB.PC00.LPCB.ECDV.PATM)
                    }
                }
            }

            Name (GTSH, 0x28)
            Name (LSTM, Zero)
            Method (_DTI, 1, NotSerialized)  // _DTI: Device Temperature Indication
            {
                LSTM = Arg0
                Notify (\_SB.PC00.LPCB.ECDV.NGFF, 0x91) // Device-Specific
            }

            Method (_NTT, 0, NotSerialized)  // _NTT: Notification Temperature Threshold
            {
                Return (0x0ADE)
            }

            Name (S2PV, 0x5A)
            Name (S2CC, 0x7F)
            Name (S2C3, 0x46)
            Name (S2HP, 0x5F)
            Name (SSP2, Zero)
            Method (_TSP, 0, Serialized)  // _TSP: Thermal Sampling Period
            {
                Return (SSP2) /* \_SB_.PC00.LPCB.ECDV.NGFF.SSP2 */
            }

            Method (_PSV, 0, Serialized)  // _PSV: Passive Temperature
            {
                Return (\_SB.IETM.CTOK (S2PV))
            }

            Method (_CRT, 0, Serialized)  // _CRT: Critical Temperature
            {
                Return (\_SB.IETM.CTOK (S2CC))
            }

            Method (_HOT, 0, Serialized)  // _HOT: Hot Temperature
            {
                Return (\_SB.IETM.CTOK (S2HP))
            }
        }
    }

    Scope (\_SB.PC00.LPCB.ECDV)
    {
        Device (TSKN)
        {
            Name (_HID, "INTC1046")  // _HID: Hardware ID
            Name (_UID, "TSKN")  // _UID: Unique ID
            Name (_STR, Unicode ("Skin Temperature Sensor(HT1)"))  // _STR: Description String
            Name (PTYP, 0x03)
            Name (CTYP, Zero)
            Name (PFLG, Zero)
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((\S1DE == One))
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_TMP, 0, Serialized)  // _TMP: Temperature
            {
                If (\ECRD)
                {
                    Local0 = \_SB.PC00.LPCB.ECDV.KDRT (One)
                    Return ((0x0AAC + (Local0 * 0x0A)))
                }
                Else
                {
                    Return (0x0BB8)
                }
            }

            Name (PATC, 0x02)
            Method (PAT0, 1, Serialized)
            {
                If (\ECRD)
                {
                    Local0 = Acquire (\_SB.PC00.LPCB.ECDV.PATM, 0x0064)
                    If ((Local0 == Zero))
                    {
                        Local1 = \_SB.IETM.KTOC (Arg0)
                        \_SB.PC00.LPCB.ECDV.DSHY (One, 0x02)
                        \_SB.PC00.LPCB.ECDV.DSTL (One, Local1)
                        Release (\_SB.PC00.LPCB.ECDV.PATM)
                    }
                }
            }

            Method (PAT1, 1, Serialized)
            {
                If (\ECRD)
                {
                    Local0 = Acquire (\_SB.PC00.LPCB.ECDV.PATM, 0x0064)
                    If ((Local0 == Zero))
                    {
                        Local1 = \_SB.IETM.KTOC (Arg0)
                        \_SB.PC00.LPCB.ECDV.DSHY (One, 0x02)
                        \_SB.PC00.LPCB.ECDV.DSTH (One, Local1)
                        Release (\_SB.PC00.LPCB.ECDV.PATM)
                    }
                }
            }

            Name (GTSH, 0x28)
            Name (LSTM, Zero)
            Method (_DTI, 1, NotSerialized)  // _DTI: Device Temperature Indication
            {
                LSTM = Arg0
                Notify (\_SB.PC00.LPCB.ECDV.TSKN, 0x91) // Device-Specific
            }

            Method (_NTT, 0, NotSerialized)  // _NTT: Notification Temperature Threshold
            {
                Return (0x0ADE)
            }

            Name (S1PV, 0x5A)
            Name (S1CC, 0x7F)
            Name (S1C3, 0x7F)
            Name (S1HP, 0x7F)
            Name (SSP1, Zero)
            Method (_TSP, 0, Serialized)  // _TSP: Thermal Sampling Period
            {
                Return (SSP1) /* \_SB_.PC00.LPCB.ECDV.TSKN.SSP1 */
            }

            Method (_PSV, 0, Serialized)  // _PSV: Passive Temperature
            {
                Return (\_SB.IETM.CTOK (S1PV))
            }

            Method (_CRT, 0, Serialized)  // _CRT: Critical Temperature
            {
                Return (\_SB.IETM.CTOK (S1CC))
            }

            Method (_CR3, 0, Serialized)  // _CR3: Warm/Standby Temperature
            {
                Return (\_SB.IETM.CTOK (S1C3))
            }

            Method (_HOT, 0, Serialized)  // _HOT: Hot Temperature
            {
                Return (\_SB.IETM.CTOK (S1HP))
            }
        }
    }

    Scope (\_SB.PC00.LPCB.ECDV)
    {
        Device (TMEM)
        {
            Name (_HID, "INTC1046")  // _HID: Hardware ID
            Name (_UID, "TMEM")  // _UID: Unique ID
            Name (_STR, Unicode ("Memory Participant"))  // _STR: Description String
            Name (PTYP, 0x03)
            Name (CTYP, Zero)
            Name (PFLG, Zero)
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((\S4DE == One))
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_TMP, 0, Serialized)  // _TMP: Temperature
            {
                If (\ECRD)
                {
                    Local0 = \_SB.PC00.LPCB.ECDV.KDRT (0x04)
                    Return ((0x0AAC + (Local0 * 0x0A)))
                }
                Else
                {
                    Return (0x0BB8)
                }
            }

            Name (PATC, 0x02)
            Method (PAT0, 1, Serialized)
            {
                If (\ECRD)
                {
                    Local0 = Acquire (\_SB.PC00.LPCB.ECDV.PATM, 0x0064)
                    If ((Local0 == Zero))
                    {
                        Local1 = \_SB.IETM.KTOC (Arg0)
                        \_SB.PC00.LPCB.ECDV.DSHY (0x04, 0x02)
                        \_SB.PC00.LPCB.ECDV.DSTL (0x04, Local1)
                        Release (\_SB.PC00.LPCB.ECDV.PATM)
                    }
                }
            }

            Method (PAT1, 1, Serialized)
            {
                If (\ECRD)
                {
                    Local0 = Acquire (\_SB.PC00.LPCB.ECDV.PATM, 0x0064)
                    If ((Local0 == Zero))
                    {
                        Local1 = \_SB.IETM.KTOC (Arg0)
                        \_SB.PC00.LPCB.ECDV.DSHY (0x04, 0x02)
                        \_SB.PC00.LPCB.ECDV.DSTH (0x04, Local1)
                        Release (\_SB.PC00.LPCB.ECDV.PATM)
                    }
                }
            }

            Name (GTSH, 0x28)
            Name (LSTM, Zero)
            Method (_DTI, 1, NotSerialized)  // _DTI: Device Temperature Indication
            {
                LSTM = Arg0
                Notify (\_SB.PC00.LPCB.ECDV.TMEM, 0x91) // Device-Specific
            }

            Method (_NTT, 0, NotSerialized)  // _NTT: Notification Temperature Threshold
            {
                Return (0x0ADE)
            }

            Name (S4PV, 0x3C)
            Name (S4CC, 0x7F)
            Name (S4C3, 0x7F)
            Name (S4HP, 0x7F)
            Name (SSP4, Zero)
            Method (_TSP, 0, Serialized)  // _TSP: Thermal Sampling Period
            {
                Return (SSP4) /* \_SB_.PC00.LPCB.ECDV.TMEM.SSP4 */
            }

            Method (_PSV, 0, Serialized)  // _PSV: Passive Temperature
            {
                Return (\_SB.IETM.CTOK (S4PV))
            }

            Method (_CRT, 0, Serialized)  // _CRT: Critical Temperature
            {
                Return (\_SB.IETM.CTOK (S4CC))
            }

            Method (_CR3, 0, Serialized)  // _CR3: Warm/Standby Temperature
            {
                Return (\_SB.IETM.CTOK (S4C3))
            }

            Method (_HOT, 0, Serialized)  // _HOT: Hot Temperature
            {
                Return (\_SB.IETM.CTOK (S4HP))
            }
        }
    }

    Scope (\_SB.PC00.LPCB.ECDV)
    {
        Device (AMBF)
        {
            Name (_HID, "INTC1046")  // _HID: Hardware ID
            Name (_UID, "AMBF")  // _UID: Unique ID
            Name (_STR, Unicode ("AMB and Near Fan Temperature (QE3)"))  // _STR: Description String
            Name (PTYP, 0x03)
            Name (CTYP, Zero)
            Name (PFLG, Zero)
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((\S5DE == One))
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_TMP, 0, Serialized)  // _TMP: Temperature
            {
                If (\ECRD)
                {
                    Local0 = \_SB.PC00.LPCB.ECDV.KDRT (0x05)
                    Return ((0x0AAC + (Local0 * 0x0A)))
                }
                Else
                {
                    Return (0x0BB8)
                }
            }

            Name (PATC, 0x02)
            Method (PAT0, 1, Serialized)
            {
                If (\ECRD)
                {
                    Local0 = Acquire (\_SB.PC00.LPCB.ECDV.PATM, 0x0064)
                    If ((Local0 == Zero))
                    {
                        Local1 = \_SB.IETM.KTOC (Arg0)
                        \_SB.PC00.LPCB.ECDV.DSHY (0x05, 0x02)
                        \_SB.PC00.LPCB.ECDV.DSTL (0x05, Local1)
                        Release (\_SB.PC00.LPCB.ECDV.PATM)
                    }
                }
            }

            Method (PAT1, 1, Serialized)
            {
                If (\ECRD)
                {
                    Local0 = Acquire (\_SB.PC00.LPCB.ECDV.PATM, 0x0064)
                    If ((Local0 == Zero))
                    {
                        Local1 = \_SB.IETM.KTOC (Arg0)
                        \_SB.PC00.LPCB.ECDV.DSHY (0x05, 0x02)
                        \_SB.PC00.LPCB.ECDV.DSTH (0x05, Local1)
                        Release (\_SB.PC00.LPCB.ECDV.PATM)
                    }
                }
            }

            Name (GTSH, 0x28)
            Name (LSTM, Zero)
            Method (_DTI, 1, NotSerialized)  // _DTI: Device Temperature Indication
            {
                LSTM = Arg0
                Notify (\_SB.PC00.LPCB.ECDV.AMBF, 0x91) // Device-Specific
            }

            Method (_NTT, 0, NotSerialized)  // _NTT: Notification Temperature Threshold
            {
                Return (0x0ADE)
            }

            Name (S5PV, 0x41)
            Name (S5CC, 0x3D)
            Name (S5C3, 0x37)
            Name (S5HP, 0x3A)
            Name (SSP5, Zero)
            Method (_TSP, 0, Serialized)  // _TSP: Thermal Sampling Period
            {
                Return (SSP5) /* \_SB_.PC00.LPCB.ECDV.AMBF.SSP5 */
            }

            Method (_PSV, 0, Serialized)  // _PSV: Passive Temperature
            {
                Return (\_SB.IETM.CTOK (S5PV))
            }

            Method (_CRT, 0, Serialized)  // _CRT: Critical Temperature
            {
                Return (\_SB.IETM.CTOK (S5CC))
            }

            Method (_CR3, 0, Serialized)  // _CR3: Warm/Standby Temperature
            {
                Return (\_SB.IETM.CTOK (S5C3))
            }

            Method (_HOT, 0, Serialized)  // _HOT: Hot Temperature
            {
                Return (\_SB.IETM.CTOK (S5HP))
            }
        }
    }

    Scope (\_SB.PC00.LPCB.ECDV)
    {
        Device (CHRG)
        {
            Name (_HID, "INTC1046")  // _HID: Hardware ID
            Name (_UID, "CHRG")  // _UID: Unique ID
            Name (_STR, Unicode ("VR & Charger Temperature (QE10)"))  // _STR: Description String
            Name (PTYP, 0x03)
            Name (CTYP, Zero)
            Name (PFLG, Zero)
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((\S3DE == One))
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_TMP, 0, Serialized)  // _TMP: Temperature
            {
                If (\ECRD)
                {
                    Local0 = \_SB.PC00.LPCB.ECDV.KDRT (0x03)
                    Return ((0x0AAC + (Local0 * 0x0A)))
                }
                Else
                {
                    Return (0x0BB8)
                }
            }

            Name (PATC, 0x02)
            Method (PAT0, 1, Serialized)
            {
                If (\ECRD)
                {
                    Local0 = Acquire (\_SB.PC00.LPCB.ECDV.PATM, 0x0064)
                    If ((Local0 == Zero))
                    {
                        Local1 = \_SB.IETM.KTOC (Arg0)
                        \_SB.PC00.LPCB.ECDV.DSHY (0x03, 0x02)
                        \_SB.PC00.LPCB.ECDV.DSTL (0x03, Local1)
                        Release (\_SB.PC00.LPCB.ECDV.PATM)
                    }
                }
            }

            Method (PAT1, 1, Serialized)
            {
                If (\ECRD)
                {
                    Local0 = Acquire (\_SB.PC00.LPCB.ECDV.PATM, 0x0064)
                    If ((Local0 == Zero))
                    {
                        Local1 = \_SB.IETM.KTOC (Arg0)
                        \_SB.PC00.LPCB.ECDV.DSHY (0x03, 0x02)
                        \_SB.PC00.LPCB.ECDV.DSTH (0x03, Local1)
                        Release (\_SB.PC00.LPCB.ECDV.PATM)
                    }
                }
            }

            Name (GTSH, 0x28)
            Name (LSTM, Zero)
            Method (_DTI, 1, NotSerialized)  // _DTI: Device Temperature Indication
            {
                LSTM = Arg0
                Notify (\_SB.PC00.LPCB.ECDV.CHRG, 0x91) // Device-Specific
            }

            Method (_NTT, 0, NotSerialized)  // _NTT: Notification Temperature Threshold
            {
                Return (0x0ADE)
            }

            Name (S3PV, 0x3C)
            Name (S3CC, 0x7F)
            Name (S3C3, 0x7F)
            Name (S3HP, 0x7F)
            Name (SSP3, Zero)
            Method (_TSP, 0, Serialized)  // _TSP: Thermal Sampling Period
            {
                Return (SSP3) /* \_SB_.PC00.LPCB.ECDV.CHRG.SSP3 */
            }

            Method (_PSV, 0, Serialized)  // _PSV: Passive Temperature
            {
                Return (\_SB.IETM.CTOK (S3PV))
            }

            Method (_CRT, 0, Serialized)  // _CRT: Critical Temperature
            {
                Return (\_SB.IETM.CTOK (S3CC))
            }

            Method (_CR3, 0, Serialized)  // _CR3: Warm/Standby Temperature
            {
                Return (\_SB.IETM.CTOK (S3C3))
            }

            Method (_HOT, 0, Serialized)  // _HOT: Hot Temperature
            {
                Return (\_SB.IETM.CTOK (S3HP))
            }
        }
    }

    Scope (\_SB.IETM)
    {
        Name (TRT0, Package (0x04)
        {
            Package (0x08)
            {
                \_SB.PC00.TCPU, , 
                \_SB.PC00.LPCB.ECDV.TSKN, , 
                0x1E, 
                0x96, 
                Zero, 
                Zero, 
                Zero, 
                Zero
            }, 

            Package (0x08)
            {
                \_SB.PC00.TCPU, , 
                \_SB.PC00.LPCB.ECDV.TMEM, , 
                0x28, 
                0x64, 
                Zero, 
                Zero, 
                Zero, 
                Zero
            }, 

            Package (0x08)
            {
                \_SB.PC00.TCPU, , 
                \_SB.PC00.LPCB.ECDV.AMBF, , 
                0x14, 
                0xC8, 
                Zero, 
                Zero, 
                Zero, 
                Zero
            }, 

            Package (0x08)
            {
                \_SB.PC00.TCPU, , 
                \_SB.PC00.LPCB.ECDV.NGFF, , 
                0x14, 
                0xC8, 
                Zero, 
                Zero, 
                Zero, 
                Zero
            }
        })
        Method (_TRT, 0, NotSerialized)  // _TRT: Thermal Relationship Table
        {
            Return (TRT0) /* \_SB_.IETM.TRT0 */
        }
    }

    Scope (\_SB.IETM)
    {
        Name (PTTL, 0x14)
        Name (PSVT, Package (0x01)
        {
            0x02
        })
    }

    Scope (\_SB.IETM)
    {
        Name (DP2P, Package (0x01)
        {
            ToUUID ("9e04115a-ae87-4d1c-9500-0f3e340bfe75") /* Unknown UUID */
        })
        Name (DPSP, Package (0x01)
        {
            ToUUID ("42a441d6-ae6a-462b-a84b-4a8ce79027d3") /* Unknown UUID */
        })
        Name (DASP, Package (0x01)
        {
            ToUUID ("3a95c389-e4b8-4629-a526-c52c88626bae") /* Unknown UUID */
        })
        Name (DA2P, Package (0x01)
        {
            ToUUID ("0e56fab6-bdfc-4e8c-8246-40ecfd4d74ea") /* Unknown UUID */
        })
        Name (DCSP, Package (0x01)
        {
            ToUUID ("97c68ae7-15fa-499c-b8c9-5da81d606e0a") /* Unknown UUID */
        })
        Name (RFIP, Package (0x01)
        {
            ToUUID ("c4ce1849-243a-49f3-b8d5-f97002f38e6a") /* Unknown UUID */
        })
        Name (DAPP, Package (0x01)
        {
            ToUUID ("63be270f-1c11-48fd-a6f7-3af253ff3e2d") /* Unknown UUID */
        })
        Name (DPID, Package (0x01)
        {
            ToUUID ("42496e14-bc1b-46e8-a798-ca915464426f") /* Unknown UUID */
        })
    }

    Name (DBD0, Package (0x01)
    {
        Buffer (0x0A2E)
        {
            /* 0000 */  0xE5, 0x1F, 0x94, 0x00, 0x00, 0x00, 0x00, 0x02,  // ........
            /* 0008 */  0x00, 0x00, 0x00, 0x40, 0x67, 0x64, 0x64, 0x76,  // ...@gddv
            /* 0010 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
            /* 0018 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
            /* 0020 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
            /* 0028 */  0x00, 0x00, 0x00, 0x00, 0x4F, 0x45, 0x4D, 0x20,  // ....OEM 
            /* 0030 */  0x45, 0x78, 0x70, 0x6F, 0x72, 0x74, 0x65, 0x64,  // Exported
            /* 0038 */  0x20, 0x44, 0x61, 0x74, 0x61, 0x56, 0x61, 0x75,  //  DataVau
            /* 0040 */  0x6C, 0x74, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // lt......
            /* 0048 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
            /* 0050 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
            /* 0058 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
            /* 0060 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
            /* 0068 */  0x00, 0x00, 0x00, 0x00, 0xFE, 0x2B, 0x38, 0x22,  // .....+8"
            /* 0070 */  0x3E, 0xCF, 0x4C, 0x84, 0xA2, 0x14, 0xB1, 0xC6,  // >.L.....
            /* 0078 */  0xD4, 0x19, 0xA4, 0x36, 0x32, 0x18, 0xD0, 0x8F,  // ...62...
            /* 0080 */  0xCF, 0x02, 0x82, 0x5C, 0xE7, 0xAD, 0xAE, 0x9F,  // ...\....
            /* 0088 */  0x19, 0xF3, 0x97, 0x87, 0x9A, 0x09, 0x00, 0x00,  // ........
            /* 0090 */  0x52, 0x45, 0x50, 0x4F, 0x5D, 0x00, 0x00, 0x00,  // REPO]...
            /* 0098 */  0x01, 0x0B, 0xA7, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
            /* 00A0 */  0x00, 0x00, 0x72, 0x87, 0xCD, 0xFF, 0x6D, 0x24,  // ..r...m$
            /* 00A8 */  0x47, 0xDB, 0x3D, 0x24, 0x92, 0xB4, 0x16, 0x6F,  // G.=$...o
            /* 00B0 */  0x45, 0xD8, 0xC3, 0xF5, 0x66, 0x14, 0x9F, 0x22,  // E...f.."
            /* 00B8 */  0xD7, 0xF7, 0xDE, 0x67, 0x90, 0x9A, 0xA2, 0x0D,  // ...g....
            /* 00C0 */  0x39, 0x25, 0xAD, 0xC3, 0x1A, 0xAD, 0x52, 0x0B,  // 9%....R.
            /* 00C8 */  0x75, 0x38, 0xE1, 0xA4, 0x14, 0x43, 0xEE, 0x27,  // u8...C.'
            /* 00D0 */  0x40, 0x46, 0xF3, 0x5F, 0x1A, 0x51, 0x4B, 0x60,  // @F._.QK`
            /* 00D8 */  0xB8, 0xE4, 0xEB, 0x25, 0x81, 0xAE, 0x99, 0x2E,  // ...%....
            /* 00E0 */  0x83, 0x14, 0x57, 0x57, 0xE1, 0x14, 0x12, 0xAF,  // ..WW....
            /* 00E8 */  0x22, 0x06, 0x4A, 0xE3, 0x8E, 0x8A, 0x30, 0xFF,  // ".J...0.
            /* 00F0 */  0x91, 0xB7, 0x14, 0xAC, 0x02, 0xD8, 0x26, 0x39,  // ......&9
            /* 00F8 */  0x75, 0x54, 0x6E, 0xAB, 0x5C, 0xEC, 0x02, 0xF7,  // uTn.\...
            /* 0100 */  0xAF, 0x79, 0x19, 0x7F, 0x2F, 0xDD, 0xBB, 0x78,  // .y../..x
            /* 0108 */  0x70, 0xD1, 0x0F, 0x7A, 0xF6, 0xA5, 0xB0, 0x73,  // p..z...s
            /* 0110 */  0x95, 0xBB, 0x5E, 0x5B, 0x73, 0x5C, 0x06, 0xA4,  // ..^[s\..
            /* 0118 */  0xEF, 0xA2, 0xD7, 0x7D, 0xF6, 0x18, 0xC0, 0x31,  // ...}...1
            /* 0120 */  0x4F, 0x45, 0xA6, 0xD6, 0xE9, 0x9E, 0xD7, 0x83,  // OE......
            /* 0128 */  0xFE, 0x13, 0x08, 0x92, 0x44, 0x32, 0x16, 0x87,  // ....D2..
            /* 0130 */  0x35, 0xF6, 0xF8, 0x26, 0x94, 0xF2, 0x36, 0x1F,  // 5..&..6.
            /* 0138 */  0x1E, 0x0E, 0xB8, 0xFB, 0x41, 0x88, 0x15, 0x6E,  // ....A..n
            /* 0140 */  0xCD, 0xAB, 0x54, 0x3F, 0x2B, 0xE7, 0x57, 0x77,  // ..T?+.Ww
            /* 0148 */  0x9A, 0x2F, 0xFE, 0xCF, 0x8E, 0xA5, 0x51, 0xF7,  // ./....Q.
            /* 0150 */  0xAE, 0x4D, 0x7C, 0x09, 0x59, 0x67, 0x7D, 0x8F,  // .M|.Yg}.
            /* 0158 */  0xA8, 0x91, 0xE7, 0x2A, 0x9A, 0xC7, 0x55, 0x17,  // ...*..U.
            /* 0160 */  0x3C, 0xC0, 0xDA, 0xF5, 0x3B, 0x67, 0xF7, 0x4D,  // <...;g.M
            /* 0168 */  0x6F, 0x91, 0x33, 0xA7, 0xF1, 0x88, 0x49, 0x81,  // o.3...I.
            /* 0170 */  0xBE, 0xF9, 0x68, 0x26, 0x72, 0x2A, 0x77, 0x0B,  // ..h&r*w.
            /* 0178 */  0x12, 0xB7, 0x0C, 0xC4, 0xC1, 0xBB, 0x3B, 0x0A,  // ......;.
            /* 0180 */  0x8F, 0xA2, 0x1E, 0xDC, 0x96, 0xE3, 0x30, 0x83,  // ......0.
            /* 0188 */  0x14, 0x54, 0x26, 0x22, 0x2E, 0xA7, 0xEB, 0x08,  // .T&"....
            /* 0190 */  0x90, 0x0E, 0x6F, 0x98, 0xB8, 0xFB, 0xCC, 0x9F,  // ..o.....
            /* 0198 */  0x1E, 0x7D, 0xCC, 0x28, 0x6D, 0x44, 0x74, 0x77,  // .}.(mDtw
            /* 01A0 */  0x51, 0x66, 0x83, 0xC4, 0x8E, 0xCA, 0xE8, 0xD9,  // Qf......
            /* 01A8 */  0x25, 0xA0, 0xC3, 0x2E, 0xF9, 0xF9, 0x2C, 0xE1,  // %.....,.
            /* 01B0 */  0xE7, 0x64, 0x34, 0x2F, 0x62, 0x61, 0x1D, 0x93,  // .d4/ba..
            /* 01B8 */  0x17, 0xD9, 0x56, 0x2A, 0x62, 0xF2, 0x2D, 0xD1,  // ..V*b.-.
            /* 01C0 */  0xCF, 0x2B, 0x5E, 0x0A, 0x1E, 0xC9, 0x4A, 0xE4,  // .+^...J.
            /* 01C8 */  0x2A, 0x40, 0xB4, 0x07, 0xD0, 0x5D, 0x7C, 0x36,  // *@...]|6
            /* 01D0 */  0xB2, 0x8C, 0x91, 0x42, 0x46, 0x02, 0xCE, 0xE9,  // ...BF...
            /* 01D8 */  0x61, 0xE9, 0x6D, 0x07, 0xFA, 0xC0, 0xAC, 0x5A,  // a.m....Z
            /* 01E0 */  0xFD, 0x3F, 0x83, 0xCC, 0x9C, 0x0D, 0xF8, 0x8B,  // .?......
            /* 01E8 */  0x25, 0x7B, 0xBC, 0x87, 0x9C, 0x61, 0x15, 0xBD,  // %{...a..
            /* 01F0 */  0x4C, 0x2D, 0xEA, 0xA6, 0x9E, 0x99, 0x73, 0x22,  // L-....s"
            /* 01F8 */  0x22, 0x96, 0x28, 0x71, 0x79, 0xDE, 0x59, 0x71,  // ".(qy.Yq
            /* 0200 */  0xBC, 0x90, 0x4B, 0xDB, 0xA0, 0xD9, 0xBB, 0x12,  // ..K.....
            /* 0208 */  0xBD, 0x2A, 0xB2, 0xA8, 0x25, 0x6D, 0xF3, 0x90,  // .*..%m..
            /* 0210 */  0x95, 0xEA, 0x22, 0x70, 0xF9, 0xD6, 0x59, 0x04,  // .."p..Y.
            /* 0218 */  0xD9, 0x2E, 0xCF, 0x50, 0x78, 0x41, 0x93, 0xC4,  // ...PxA..
            /* 0220 */  0xA2, 0x3F, 0x55, 0x1A, 0x69, 0x47, 0x01, 0xF4,  // .?U.iG..
            /* 0228 */  0x8F, 0xB4, 0xDD, 0x6B, 0x9F, 0x66, 0x97, 0x09,  // ...k.f..
            /* 0230 */  0x65, 0x1B, 0x63, 0xF1, 0xE0, 0x37, 0x95, 0x2C,  // e.c..7.,
            /* 0238 */  0x36, 0x00, 0xC6, 0x9D, 0xD6, 0xA6, 0xE5, 0x7C,  // 6......|
            /* 0240 */  0xF8, 0xF6, 0x93, 0x81, 0xC9, 0x4D, 0x03, 0x5C,  // .....M.\
            /* 0248 */  0x0B, 0xFE, 0x83, 0xCC, 0xD2, 0x81, 0xD3, 0x64,  // .......d
            /* 0250 */  0x3A, 0xD3, 0x07, 0x70, 0x7D, 0xEA, 0x23, 0x95,  // :..p}.#.
            /* 0258 */  0x2C, 0xF5, 0xC3, 0x57, 0xEB, 0x9E, 0x06, 0xE0,  // ,..W....
            /* 0260 */  0x6E, 0x5D, 0x32, 0x6A, 0x8C, 0x67, 0xF7, 0xC4,  // n]2j.g..
            /* 0268 */  0xAF, 0x15, 0x35, 0xD0, 0x4F, 0x38, 0x21, 0xC4,  // ..5.O8!.
            /* 0270 */  0x36, 0xB5, 0xB4, 0x40, 0x52, 0x7E, 0xD3, 0x22,  // 6..@R~."
            /* 0278 */  0x34, 0x42, 0x94, 0x96, 0xE6, 0xF5, 0xEB, 0xEA,  // 4B......
            /* 0280 */  0xA4, 0x1F, 0x21, 0xED, 0x37, 0xF9, 0xBB, 0x5E,  // ..!.7..^
            /* 0288 */  0xC2, 0x1A, 0x24, 0x80, 0x53, 0x66, 0x4C, 0x3F,  // ..$.SfL?
            /* 0290 */  0x22, 0x39, 0xCA, 0xCE, 0x86, 0xA6, 0x94, 0xD3,  // "9......
            /* 0298 */  0x8B, 0xD7, 0x3D, 0x6C, 0xE4, 0x39, 0x22, 0x06,  // ..=l.9".
            /* 02A0 */  0xEC, 0x94, 0xAA, 0x64, 0xA2, 0x80, 0xD3, 0x0C,  // ...d....
            /* 02A8 */  0x9E, 0x62, 0x9F, 0x61, 0x63, 0x5D, 0x33, 0x42,  // .b.ac]3B
            /* 02B0 */  0x63, 0x59, 0xD3, 0x7D, 0x2B, 0x9D, 0x8C, 0xB5,  // cY.}+...
            /* 02B8 */  0x8D, 0xE1, 0x67, 0x8C, 0xAA, 0x6E, 0xFB, 0xA7,  // ..g..n..
            /* 02C0 */  0x89, 0xEE, 0x05, 0x2C, 0x2B, 0x69, 0x6D, 0xC3,  // ...,+im.
            /* 02C8 */  0x5A, 0xCE, 0xDE, 0xB7, 0xA0, 0x66, 0x67, 0xC0,  // Z....fg.
            /* 02D0 */  0x5A, 0xF1, 0x44, 0x31, 0x97, 0x88, 0x0C, 0x91,  // Z.D1....
            /* 02D8 */  0x3C, 0xBC, 0x13, 0x3D, 0xDD, 0xB4, 0xB3, 0x6F,  // <..=...o
            /* 02E0 */  0xC2, 0x26, 0x6B, 0xFA, 0xAC, 0x46, 0x5B, 0x01,  // .&k..F[.
            /* 02E8 */  0x8C, 0x30, 0x8D, 0x23, 0xB2, 0xCD, 0xEA, 0x4E,  // .0.#...N
            /* 02F0 */  0x6A, 0x30, 0x5A, 0x8A, 0xCF, 0xA0, 0x46, 0x01,  // j0Z...F.
            /* 02F8 */  0x83, 0x2A, 0x1C, 0x84, 0x66, 0xB2, 0x35, 0x5F,  // .*..f.5_
            /* 0300 */  0x54, 0xCE, 0x42, 0x04, 0x5E, 0x8F, 0x4A, 0x7A,  // T.B.^.Jz
            /* 0308 */  0xD8, 0xAA, 0x50, 0x29, 0x42, 0x93, 0xB8, 0x29,  // ..P)B..)
            /* 0310 */  0xB0, 0x0A, 0x71, 0x4F, 0xAE, 0x82, 0xC6, 0xA7,  // ..qO....
            /* 0318 */  0x09, 0xB9, 0x6D, 0xB3, 0x7C, 0x2D, 0x05, 0x55,  // ..m.|-.U
            /* 0320 */  0x21, 0x30, 0x69, 0xD7, 0x4B, 0x34, 0xB7, 0xC4,  // !0i.K4..
            /* 0328 */  0xB0, 0x54, 0x07, 0x16, 0x0F, 0xF3, 0xAB, 0x93,  // .T......
            /* 0330 */  0xC9, 0x22, 0x8A, 0xD1, 0x99, 0xC0, 0x75, 0xFC,  // ."....u.
            /* 0338 */  0xF7, 0x3F, 0x41, 0x4E, 0xEF, 0x6C, 0x3B, 0x3F,  // .?AN.l;?
            /* 0340 */  0x1B, 0xFB, 0x06, 0x00, 0x46, 0x47, 0x61, 0xEE,  // ....FGa.
            /* 0348 */  0xB7, 0x52, 0x35, 0xF7, 0x14, 0xE3, 0x63, 0x6A,  // .R5...cj
            /* 0350 */  0x38, 0x87, 0x43, 0x4E, 0x46, 0xCD, 0x6D, 0x83,  // 8.CNF.m.
            /* 0358 */  0x49, 0x2F, 0x9A, 0x1A, 0x63, 0xC8, 0x71, 0xD6,  // I/..c.q.
            /* 0360 */  0x6F, 0x87, 0xFE, 0xB4, 0x70, 0xE5, 0xD1, 0x2B,  // o...p..+
            /* 0368 */  0x3D, 0xD0, 0x94, 0xEE, 0x57, 0x62, 0x76, 0x87,  // =...Wbv.
            /* 0370 */  0xCF, 0x53, 0xB3, 0xCC, 0x4A, 0x2B, 0xCC, 0xB0,  // .S..J+..
            /* 0378 */  0xC2, 0x86, 0xB2, 0xE3, 0xB9, 0xE3, 0xD2, 0x7A,  // .......z
            /* 0380 */  0xAB, 0x3E, 0x56, 0xDC, 0xBD, 0xDF, 0x85, 0x82,  // .>V.....
            /* 0388 */  0x35, 0x46, 0xB1, 0x0A, 0xC1, 0x46, 0xF8, 0x8B,  // 5F...F..
            /* 0390 */  0x6D, 0xEA, 0x2C, 0xD5, 0x6A, 0x97, 0x12, 0x5B,  // m.,.j..[
            /* 0398 */  0xCB, 0x0A, 0x31, 0x9B, 0xA0, 0x87, 0x6C, 0xA1,  // ..1...l.
            /* 03A0 */  0xC3, 0xE7, 0x33, 0x19, 0xB8, 0x0C, 0x23, 0x8E,  // ..3...#.
            /* 03A8 */  0x33, 0x2C, 0x4F, 0x64, 0xCA, 0xCC, 0xDE, 0x50,  // 3,Od...P
            /* 03B0 */  0x6E, 0xBD, 0x89, 0x62, 0xD3, 0x68, 0x59, 0x11,  // n..b.hY.
            /* 03B8 */  0xE0, 0xA4, 0x51, 0x25, 0xDE, 0x5D, 0xA8, 0xAD,  // ..Q%.]..
            /* 03C0 */  0x4A, 0xC1, 0x67, 0x70, 0x7A, 0xF2, 0x8E, 0x4A,  // J.gpz..J
            /* 03C8 */  0x71, 0x58, 0x9C, 0x5F, 0x06, 0xA9, 0x0C, 0xED,  // qX._....
            /* 03D0 */  0x79, 0x26, 0xA4, 0xA8, 0x6C, 0x01, 0xC8, 0x37,  // y&..l..7
            /* 03D8 */  0x74, 0xC4, 0xFA, 0xD5, 0x7D, 0xD0, 0xAC, 0xE6,  // t...}...
            /* 03E0 */  0x5B, 0x46, 0x09, 0x75, 0x1C, 0xF1, 0x16, 0x2A,  // [F.u...*
            /* 03E8 */  0x94, 0x95, 0x5A, 0x64, 0x41, 0xD7, 0xA9, 0x8C,  // ..ZdA...
            /* 03F0 */  0xE6, 0x9F, 0x58, 0x1A, 0x05, 0x10, 0x30, 0x9D,  // ..X...0.
            /* 03F8 */  0x3B, 0x31, 0x8F, 0x1A, 0x33, 0xC1, 0x53, 0x9A,  // ;1..3.S.
            /* 0400 */  0x4D, 0x36, 0xFD, 0x0B, 0xF3, 0x7C, 0x31, 0xD9,  // M6...|1.
            /* 0408 */  0x31, 0x24, 0x4A, 0x58, 0xCC, 0x99, 0xE1, 0x4F,  // 1$JX...O
            /* 0410 */  0x08, 0xD6, 0xAD, 0x42, 0xE4, 0xCC, 0x6D, 0x13,  // ...B..m.
            /* 0418 */  0xEA, 0x4E, 0xD2, 0xE7, 0xCC, 0x6D, 0x7B, 0x87,  // .N...m{.
            /* 0420 */  0xB5, 0x5F, 0x15, 0xB4, 0xE4, 0x98, 0xED, 0xD9,  // ._......
            /* 0428 */  0x3B, 0x59, 0xA2, 0xAB, 0x44, 0x5B, 0xBD, 0x80,  // ;Y..D[..
            /* 0430 */  0x3E, 0x53, 0x49, 0xE3, 0xDE, 0xF8, 0xC3, 0x49,  // >SI....I
            /* 0438 */  0x51, 0xCD, 0x7B, 0xA4, 0x1B, 0x3E, 0x5F, 0x5B,  // Q.{..>_[
            /* 0440 */  0xD4, 0x14, 0xB9, 0xA8, 0x76, 0xAC, 0xF2, 0xD4,  // ....v...
            /* 0448 */  0xA5, 0xAA, 0x54, 0x9A, 0xC2, 0x2A, 0x97, 0x8D,  // ..T..*..
            /* 0450 */  0xA5, 0xC8, 0x6F, 0x71, 0x93, 0x3F, 0x84, 0x38,  // ..oq.?.8
            /* 0458 */  0x3F, 0xA4, 0xB4, 0x27, 0x6B, 0x94, 0x88, 0x55,  // ?..'k..U
            /* 0460 */  0x9A, 0x45, 0xFA, 0xC3, 0xB4, 0xE3, 0x27, 0x6C,  // .E....'l
            /* 0468 */  0x5E, 0xEB, 0x6D, 0x37, 0xCD, 0xFF, 0xD4, 0x17,  // ^.m7....
            /* 0470 */  0xE1, 0x9A, 0x4A, 0x30, 0xBC, 0x0E, 0x13, 0x78,  // ..J0...x
            /* 0478 */  0x5D, 0x15, 0xFF, 0x9D, 0x50, 0x28, 0xCE, 0x66,  // ]...P(.f
            /* 0480 */  0x3E, 0x12, 0x83, 0xFA, 0x4E, 0xAD, 0x43, 0xEC,  // >...N.C.
            /* 0488 */  0x85, 0x88, 0x25, 0xE0, 0x72, 0x92, 0x02, 0xB2,  // ..%.r...
            /* 0490 */  0x06, 0x63, 0x07, 0x41, 0xCA, 0x8F, 0xCF, 0x7D,  // .c.A...}
            /* 0498 */  0x24, 0xC7, 0xAD, 0xC3, 0x20, 0xF2, 0x94, 0xF2,  // $... ...
            /* 04A0 */  0x0A, 0x1D, 0x10, 0xEE, 0x60, 0x6A, 0xF3, 0x33,  // ....`j.3
            /* 04A8 */  0x60, 0xDB, 0xEB, 0x2A, 0xA8, 0x46, 0xA1, 0x71,  // `..*.F.q
            /* 04B0 */  0x10, 0x92, 0x18, 0xED, 0x8C, 0xA1, 0xB0, 0xC6,  // ........
            /* 04B8 */  0x6A, 0x7E, 0x3B, 0x48, 0x2F, 0x29, 0x9A, 0x73,  // j~;H/).s
            /* 04C0 */  0x4B, 0x9D, 0x10, 0x42, 0x8B, 0x18, 0x74, 0x24,  // K..B..t$
            /* 04C8 */  0xEC, 0xF9, 0x84, 0xA5, 0xA1, 0x0F, 0xD7, 0x2E,  // ........
            /* 04D0 */  0xE1, 0xD6, 0x5B, 0xC2, 0x8B, 0x62, 0xB2, 0xD8,  // ..[..b..
            /* 04D8 */  0x36, 0x76, 0xC6, 0x40, 0x40, 0x8F, 0xC1, 0xEA,  // 6v.@@...
            /* 04E0 */  0xAE, 0x7C, 0xA0, 0xEE, 0xDB, 0x5A, 0x14, 0x02,  // .|...Z..
            /* 04E8 */  0xE0, 0x39, 0x3B, 0xE9, 0x7D, 0x02, 0x21, 0xE2,  // .9;.}.!.
            /* 04F0 */  0x40, 0xB7, 0x89, 0x0D, 0x0B, 0x23, 0x78, 0x60,  // @....#x`
            /* 04F8 */  0xFB, 0x13, 0x1B, 0xD9, 0x5E, 0xE5, 0x65, 0x00,  // ....^.e.
            /* 0500 */  0x6A, 0x13, 0x77, 0x3F, 0xC8, 0xF4, 0x5B, 0xE5,  // j.w?..[.
            /* 0508 */  0xA6, 0x0B, 0xA1, 0x12, 0x38, 0xEF, 0x68, 0x6B,  // ....8.hk
            /* 0510 */  0x0B, 0x32, 0x8D, 0x56, 0xF2, 0xD4, 0x29, 0x64,  // .2.V..)d
            /* 0518 */  0x46, 0x60, 0xBF, 0x2E, 0x3D, 0x3F, 0xD0, 0xE8,  // F`..=?..
            /* 0520 */  0xBE, 0x5D, 0x52, 0x3F, 0x53, 0x97, 0x5E, 0xE1,  // .]R?S.^.
            /* 0528 */  0x9D, 0xBD, 0x85, 0x7F, 0x96, 0x27, 0x05, 0xDE,  // .....'..
            /* 0530 */  0x76, 0x48, 0x32, 0x41, 0x6A, 0x69, 0x04, 0xEE,  // vH2Aji..
            /* 0538 */  0x47, 0x1B, 0x24, 0xE8, 0xBE, 0x0D, 0x3D, 0x4D,  // G.$...=M
            /* 0540 */  0xB5, 0x4D, 0x61, 0x3D, 0x2B, 0x2C, 0x20, 0xAD,  // .Ma=+, .
            /* 0548 */  0xAD, 0x6D, 0x16, 0x13, 0x69, 0x53, 0x02, 0x6E,  // .m..iS.n
            /* 0550 */  0xB7, 0x80, 0xF9, 0x07, 0xEA, 0xE2, 0xD0, 0x87,  // ........
            /* 0558 */  0x35, 0x01, 0x3F, 0xEC, 0x25, 0x53, 0xA3, 0x2A,  // 5.?.%S.*
            /* 0560 */  0xB1, 0x32, 0x25, 0x73, 0xE7, 0x1E, 0xE0, 0xDB,  // .2%s....
            /* 0568 */  0x86, 0x3B, 0x7C, 0x8C, 0x1F, 0x91, 0xF6, 0xF1,  // .;|.....
            /* 0570 */  0x9B, 0x14, 0x4D, 0xC0, 0x98, 0x41, 0x85, 0x9E,  // ..M..A..
            /* 0578 */  0xFF, 0x61, 0x30, 0x65, 0x41, 0xBE, 0x01, 0xE1,  // .a0eA...
            /* 0580 */  0x44, 0xAB, 0xE4, 0xE6, 0x90, 0xFC, 0x7E, 0xA6,  // D.....~.
            /* 0588 */  0x59, 0x74, 0xC9, 0x7B, 0x75, 0x9C, 0x89, 0x88,  // Yt.{u...
            /* 0590 */  0x7A, 0x21, 0xD0, 0xB6, 0x5B, 0x33, 0xBE, 0x47,  // z!..[3.G
            /* 0598 */  0xB4, 0xBE, 0xA0, 0xA0, 0xD6, 0x1C, 0xAC, 0xE2,  // ........
            /* 05A0 */  0xB1, 0xE5, 0x1D, 0x74, 0xDA, 0xC9, 0x8D, 0xB5,  // ...t....
            /* 05A8 */  0x68, 0xED, 0x2F, 0x84, 0x76, 0x36, 0xFC, 0xFD,  // h./.v6..
            /* 05B0 */  0x9A, 0x36, 0x8A, 0x8C, 0xDD, 0x4A, 0xA0, 0xEF,  // .6...J..
            /* 05B8 */  0x95, 0xB4, 0x4C, 0x27, 0x9C, 0x19, 0x9A, 0x87,  // ..L'....
            /* 05C0 */  0x87, 0x7C, 0x38, 0x4F, 0xD8, 0x82, 0x38, 0xEF,  // .|8O..8.
            /* 05C8 */  0x1F, 0xC5, 0x6B, 0x06, 0x63, 0xCC, 0x7F, 0xCF,  // ..k.c...
            /* 05D0 */  0x47, 0x54, 0x36, 0x0D, 0x38, 0x20, 0x44, 0xAE,  // GT6.8 D.
            /* 05D8 */  0x0C, 0xC5, 0x25, 0xB7, 0xA2, 0xA9, 0xF2, 0x24,  // ..%....$
            /* 05E0 */  0x0C, 0xAC, 0x52, 0x88, 0xFC, 0x84, 0x1B, 0x0D,  // ..R.....
            /* 05E8 */  0x96, 0x1C, 0x30, 0x1D, 0x5C, 0xA8, 0xE5, 0xAC,  // ..0.\...
            /* 05F0 */  0xCE, 0xDB, 0x31, 0x69, 0x1B, 0x5C, 0xF0, 0x72,  // ..1i.\.r
            /* 05F8 */  0x9D, 0xD6, 0xAD, 0x1F, 0x46, 0x4B, 0x1D, 0xA1,  // ....FK..
            /* 0600 */  0x6A, 0x42, 0xB6, 0x0C, 0xBF, 0xA9, 0x48, 0x2D,  // jB....H-
            /* 0608 */  0xE6, 0x33, 0xA8, 0x95, 0xFB, 0x47, 0xCF, 0x9B,  // .3...G..
            /* 0610 */  0x45, 0x14, 0xC9, 0x12, 0x6A, 0x2B, 0x30, 0x5E,  // E...j+0^
            /* 0618 */  0xC7, 0x2F, 0x38, 0xDF, 0x32, 0xEA, 0xC1, 0xA6,  // ./8.2...
            /* 0620 */  0x52, 0xBA, 0xC8, 0xB1, 0x9B, 0x32, 0xBA, 0x2D,  // R....2.-
            /* 0628 */  0xF4, 0x85, 0x12, 0xDC, 0x0E, 0x02, 0xBE, 0x61,  // .......a
            /* 0630 */  0xCF, 0xCE, 0xF5, 0xE5, 0xBD, 0x32, 0x04, 0x5B,  // .....2.[
            /* 0638 */  0x19, 0xDD, 0xF9, 0x0D, 0x33, 0xC4, 0x19, 0x51,  // ....3..Q
            /* 0640 */  0x3F, 0xCC, 0xE2, 0xD7, 0xAD, 0xE0, 0xB9, 0xB7,  // ?.......
            /* 0648 */  0x47, 0xB6, 0xD7, 0x53, 0x88, 0x14, 0x45, 0x26,  // G..S..E&
            /* 0650 */  0x0B, 0x92, 0x5F, 0xF9, 0xDF, 0x66, 0x2C, 0x24,  // .._..f,$
            /* 0658 */  0xAF, 0xAD, 0x78, 0x86, 0xAF, 0xA4, 0xDD, 0x0E,  // ..x.....
            /* 0660 */  0x7B, 0xC2, 0x55, 0x0D, 0x5C, 0xCE, 0x30, 0xA1,  // {.U.\.0.
            /* 0668 */  0x62, 0x1A, 0xCF, 0x84, 0xF9, 0xC8, 0x96, 0xB8,  // b.......
            /* 0670 */  0x8F, 0x6F, 0x50, 0x26, 0xAB, 0xBB, 0x19, 0x3B,  // .oP&...;
            /* 0678 */  0xEF, 0x55, 0x87, 0xFA, 0xE2, 0xBF, 0xB8, 0x6A,  // .U.....j
            /* 0680 */  0x09, 0x7B, 0x98, 0x39, 0x5B, 0x9D, 0x2B, 0xB8,  // .{.9[.+.
            /* 0688 */  0x39, 0x07, 0x70, 0xAC, 0xC3, 0xE8, 0xB9, 0xDB,  // 9.p.....
            /* 0690 */  0x5D, 0xDF, 0x44, 0x6A, 0x0B, 0xFA, 0x51, 0xB0,  // ].Dj..Q.
            /* 0698 */  0x7B, 0x69, 0x11, 0x8F, 0xA2, 0x87, 0x28, 0x82,  // {i....(.
            /* 06A0 */  0x9A, 0x22, 0x43, 0x5B, 0x7E, 0x16, 0xA6, 0x77,  // ."C[~..w
            /* 06A8 */  0x31, 0x7B, 0x9B, 0x43, 0x43, 0x6D, 0x82, 0xF0,  // 1{.CCm..
            /* 06B0 */  0x94, 0x30, 0x89, 0x10, 0x15, 0x1B, 0xAE, 0xCB,  // .0......
            /* 06B8 */  0xBB, 0x2E, 0xEC, 0x0A, 0x71, 0x4F, 0x29, 0x52,  // ....qO)R
            /* 06C0 */  0xB5, 0xB8, 0xC4, 0xE7, 0x2B, 0x45, 0x3F, 0xE1,  // ....+E?.
            /* 06C8 */  0xEC, 0x69, 0x22, 0x7D, 0x83, 0x8E, 0x5B, 0x13,  // .i"}..[.
            /* 06D0 */  0x17, 0x40, 0x42, 0x6E, 0xE9, 0x97, 0x09, 0x2B,  // .@Bn...+
            /* 06D8 */  0xA3, 0x56, 0xFF, 0x8A, 0x28, 0xCF, 0x6E, 0xB1,  // .V..(.n.
            /* 06E0 */  0x34, 0xE9, 0x6E, 0x69, 0x99, 0xD5, 0xE6, 0x17,  // 4.ni....
            /* 06E8 */  0x5B, 0x64, 0x66, 0xEF, 0xFE, 0x57, 0xB1, 0xA1,  // [df..W..
            /* 06F0 */  0x6F, 0x74, 0xC0, 0x4E, 0x27, 0x71, 0xA9, 0x3F,  // ot.N'q.?
            /* 06F8 */  0xCD, 0x11, 0x6B, 0x96, 0x3E, 0x1A, 0x95, 0x4F,  // ..k.>..O
            /* 0700 */  0x41, 0xC3, 0xCF, 0xB0, 0x55, 0xCF, 0x1A, 0x09,  // A...U...
            /* 0708 */  0x20, 0x9D, 0xFD, 0xB1, 0x0E, 0x41, 0xE3, 0xA1,  //  ....A..
            /* 0710 */  0xA1, 0xB9, 0xB0, 0xCE, 0xB3, 0xC9, 0x43, 0x63,  // ......Cc
            /* 0718 */  0x17, 0xE6, 0x9D, 0xAA, 0x22, 0xCD, 0xCF, 0x4F,  // ...."..O
            /* 0720 */  0xB4, 0xF4, 0x93, 0xC3, 0x0A, 0x2E, 0x09, 0x4B,  // .......K
            /* 0728 */  0xF5, 0xCD, 0xA1, 0x61, 0x3E, 0xD8, 0x66, 0x98,  // ...a>.f.
            /* 0730 */  0x56, 0xD3, 0xA9, 0x24, 0xF0, 0x9A, 0x19, 0x11,  // V..$....
            /* 0738 */  0x96, 0x33, 0x16, 0xAB, 0x39, 0x3B, 0xBF, 0xB9,  // .3..9;..
            /* 0740 */  0x79, 0xA5, 0xF8, 0x83, 0xFC, 0xE6, 0xDA, 0x9A,  // y.......
            /* 0748 */  0xDC, 0xF9, 0x99, 0x2E, 0x9C, 0x6A, 0xAE, 0x36,  // .....j.6
            /* 0750 */  0x28, 0x17, 0x15, 0x5C, 0x05, 0xB7, 0x04, 0xBE,  // (..\....
            /* 0758 */  0x86, 0x3A, 0x92, 0x60, 0x34, 0x1A, 0xD5, 0x52,  // .:.`4..R
            /* 0760 */  0x24, 0x71, 0xB5, 0x82, 0x7C, 0xAE, 0x6C, 0x01,  // $q..|.l.
            /* 0768 */  0x72, 0x9B, 0xBA, 0xF1, 0x03, 0x48, 0x96, 0x12,  // r....H..
            /* 0770 */  0xEB, 0x71, 0x2A, 0xA4, 0x6C, 0xD2, 0x8F, 0xE5,  // .q*.l...
            /* 0778 */  0xF8, 0xC5, 0xFC, 0xEB, 0x5D, 0xF4, 0x59, 0x5F,  // ....].Y_
            /* 0780 */  0xCE, 0x1B, 0x02, 0xE0, 0xE4, 0x32, 0x8F, 0x38,  // .....2.8
            /* 0788 */  0x11, 0xAC, 0x7D, 0xC0, 0x72, 0xE0, 0x40, 0x20,  // ..}.r.@ 
            /* 0790 */  0xDC, 0x6B, 0xB4, 0xB0, 0x3E, 0xD2, 0x8D, 0xC4,  // .k..>...
            /* 0798 */  0x60, 0x87, 0xD8, 0x46, 0x1E, 0xF0, 0xA8, 0x70,  // `..F...p
            /* 07A0 */  0xD0, 0xC8, 0xF7, 0x12, 0xDE, 0x0B, 0x23, 0x6F,  // ......#o
            /* 07A8 */  0x07, 0x3A, 0xED, 0x7A, 0x49, 0x5F, 0x0B, 0x5E,  // .:.zI_.^
            /* 07B0 */  0x10, 0xAF, 0x31, 0x80, 0xA6, 0x9B, 0xDA, 0x03,  // ..1.....
            /* 07B8 */  0x39, 0xEE, 0xDB, 0x96, 0x9F, 0xB9, 0xB2, 0x7F,  // 9.......
            /* 07C0 */  0x60, 0x80, 0x8F, 0xB6, 0xC3, 0x61, 0x26, 0x12,  // `....a&.
            /* 07C8 */  0x5A, 0x61, 0x8B, 0x2E, 0xE3, 0xFE, 0x44, 0x25,  // Za....D%
            /* 07D0 */  0x10, 0x26, 0x23, 0xB9, 0x18, 0xE0, 0x50, 0xEB,  // .&#...P.
            /* 07D8 */  0xA6, 0x6D, 0x82, 0xC0, 0x38, 0x11, 0x67, 0x08,  // .m..8.g.
            /* 07E0 */  0xB3, 0x56, 0xC0, 0x8E, 0x67, 0xF1, 0x1D, 0xF3,  // .V..g...
            /* 07E8 */  0x38, 0xEE, 0x26, 0xC0, 0x19, 0x02, 0x0D, 0xE6,  // 8.&.....
            /* 07F0 */  0xA8, 0x83, 0xB1, 0x27, 0x6C, 0x55, 0xF5, 0x0C,  // ...'lU..
            /* 07F8 */  0x03, 0xCF, 0x4D, 0xF7, 0xEA, 0x32, 0xD6, 0xF6,  // ..M..2..
            /* 0800 */  0x29, 0x53, 0x8E, 0x8A, 0x28, 0xF8, 0xDE, 0xE1,  // )S..(...
            /* 0808 */  0x4A, 0x79, 0xA5, 0x54, 0x6A, 0x0A, 0x90, 0xE4,  // Jy.Tj...
            /* 0810 */  0x09, 0x23, 0x59, 0xF6, 0x2E, 0x23, 0xF0, 0x2F,  // .#Y..#./
            /* 0818 */  0x09, 0xFA, 0x77, 0x47, 0x8E, 0x3A, 0x28, 0xE8,  // ..wG.:(.
            /* 0820 */  0xE1, 0xF6, 0xE1, 0x6C, 0x08, 0xE8, 0x7D, 0x01,  // ...l..}.
            /* 0828 */  0xCF, 0xB9, 0x71, 0x5F, 0x52, 0x44, 0xCE, 0x4D,  // ..q_RD.M
            /* 0830 */  0x40, 0x30, 0x58, 0xB2, 0xE4, 0x1A, 0x63, 0xEB,  // @0X...c.
            /* 0838 */  0xAE, 0x36, 0xB5, 0x76, 0x24, 0xB6, 0xD2, 0xF2,  // .6.v$...
            /* 0840 */  0x2E, 0x4F, 0x03, 0x8F, 0xBC, 0x02, 0xE6, 0x87,  // .O......
            /* 0848 */  0xBD, 0xA8, 0x38, 0x47, 0xF7, 0x4E, 0x07, 0xE5,  // ..8G.N..
            /* 0850 */  0xCD, 0xB2, 0x41, 0xD4, 0xF8, 0x1F, 0x33, 0x70,  // ..A...3p
            /* 0858 */  0x5B, 0xC8, 0xDF, 0xB0, 0xE9, 0x7A, 0x93, 0xAF,  // [....z..
            /* 0860 */  0x31, 0xEF, 0xE4, 0xC0, 0x1B, 0x50, 0x3D, 0x74,  // 1....P=t
            /* 0868 */  0x5C, 0x03, 0xE2, 0xBA, 0x08, 0x1B, 0x48, 0x60,  // \.....H`
            /* 0870 */  0x02, 0x69, 0x1A, 0x4A, 0x61, 0x33, 0x79, 0xE5,  // .i.Ja3y.
            /* 0878 */  0x16, 0xCE, 0xEE, 0x43, 0x85, 0xDB, 0xA5, 0x31,  // ...C...1
            /* 0880 */  0xB5, 0xAC, 0xC0, 0xCE, 0xBF, 0x07, 0xF1, 0xC6,  // ........
            /* 0888 */  0x85, 0xEB, 0xB1, 0xDB, 0x04, 0xDE, 0x81, 0x45,  // .......E
            /* 0890 */  0xE2, 0xD8, 0x46, 0x5A, 0x6B, 0x0E, 0x27, 0x03,  // ..FZk.'.
            /* 0898 */  0x55, 0xF0, 0xA5, 0x1F, 0xC1, 0x36, 0x3C, 0xD4,  // U....6<.
            /* 08A0 */  0x95, 0xA3, 0x2C, 0x0A, 0xE9, 0x0C, 0x4E, 0x54,  // ..,...NT
            /* 08A8 */  0xEE, 0x72, 0xBF, 0xBB, 0xF9, 0x16, 0xDE, 0xA4,  // .r......
            /* 08B0 */  0x8C, 0x58, 0x70, 0x74, 0xB2, 0x2D, 0x2A, 0xDA,  // .Xpt.-*.
            /* 08B8 */  0xF5, 0x30, 0x5A, 0xB6, 0xA0, 0xBD, 0x34, 0x59,  // .0Z...4Y
            /* 08C0 */  0x80, 0xEE, 0x4A, 0x6B, 0x61, 0xE8, 0xB3, 0xCE,  // ..Jka...
            /* 08C8 */  0x95, 0x3A, 0x2F, 0xF1, 0x14, 0xD4, 0x57, 0xDC,  // .:/...W.
            /* 08D0 */  0x6A, 0x82, 0xC8, 0xEF, 0x29, 0xE8, 0xA8, 0x0F,  // j...)...
            /* 08D8 */  0xDB, 0xC6, 0xB2, 0x5F, 0x5F, 0xE6, 0x93, 0x20,  // ...__.. 
            /* 08E0 */  0x00, 0x7A, 0xC1, 0xCE, 0x19, 0x20, 0xCD, 0x5A,  // .z... .Z
            /* 08E8 */  0x96, 0xE5, 0x3E, 0xD2, 0x29, 0xB4, 0x16, 0x36,  // ..>.)..6
            /* 08F0 */  0xE7, 0x0C, 0x47, 0x70, 0xF0, 0x82, 0xD3, 0x75,  // ..Gp...u
            /* 08F8 */  0xB0, 0xCB, 0x9B, 0xAE, 0x31, 0xE8, 0xBC, 0x77,  // ....1..w
            /* 0900 */  0x3D, 0xF7, 0x79, 0xF7, 0xE4, 0xD8, 0xDC, 0x1E,  // =.y.....
            /* 0908 */  0xB4, 0xD7, 0x19, 0x82, 0x10, 0xFF, 0x4D, 0x3E,  // ......M>
            /* 0910 */  0x80, 0x09, 0x73, 0x4C, 0x00, 0x39, 0x47, 0x63,  // ..sL.9Gc
            /* 0918 */  0x7D, 0xA9, 0x6E, 0x00, 0x7A, 0xE8, 0x82, 0xB3,  // }.n.z...
            /* 0920 */  0x7C, 0xFB, 0xAF, 0x4A, 0xAB, 0xFF, 0xD8, 0xA9,  // |..J....
            /* 0928 */  0x1A, 0x40, 0xEF, 0x5F, 0xD1, 0x2C, 0xDA, 0xE6,  // .@._.,..
            /* 0930 */  0x6B, 0x39, 0xF8, 0x1D, 0xBC, 0xB0, 0xB7, 0x8B,  // k9......
            /* 0938 */  0xBE, 0xE4, 0xE2, 0x73, 0xB6, 0xF7, 0x93, 0xB8,  // ...s....
            /* 0940 */  0x2D, 0x8A, 0x78, 0xAE, 0xAE, 0xEA, 0xE3, 0xEE,  // -.x.....
            /* 0948 */  0x8E, 0xE0, 0x5C, 0xB2, 0x89, 0x14, 0x47, 0xF8,  // ..\...G.
            /* 0950 */  0xF6, 0x94, 0x79, 0xFA, 0x3B, 0x5D, 0xEC, 0xBF,  // ..y.;]..
            /* 0958 */  0xD4, 0xDE, 0xAB, 0x59, 0xBF, 0xF8, 0x6B, 0x39,  // ...Y..k9
            /* 0960 */  0x0B, 0xCC, 0x04, 0x52, 0x54, 0x16, 0x6D, 0x24,  // ...RT.m$
            /* 0968 */  0x81, 0xA2, 0x75, 0xF6, 0x87, 0x07, 0x86, 0x2F,  // ..u..../
            /* 0970 */  0xDC, 0x36, 0x86, 0x77, 0xD7, 0x5A, 0x44, 0xDE,  // .6.w.ZD.
            /* 0978 */  0x54, 0x47, 0x74, 0xEA, 0xCD, 0x6E, 0xFC, 0xB3,  // TGt..n..
            /* 0980 */  0x10, 0x2A, 0xAC, 0x15, 0xE9, 0x32, 0x31, 0x41,  // .*...21A
            /* 0988 */  0xE3, 0x01, 0x70, 0x00, 0xAA, 0x22, 0x56, 0x97,  // ..p.."V.
            /* 0990 */  0x1B, 0x4F, 0x3A, 0x51, 0x50, 0xD7, 0x50, 0x9C,  // .O:QP.P.
            /* 0998 */  0x03, 0x36, 0x8B, 0x6B, 0x83, 0x18, 0x84, 0x70,  // .6.k...p
            /* 09A0 */  0x25, 0x87, 0xD1, 0x63, 0x6B, 0xEE, 0x13, 0xB6,  // %..ck...
            /* 09A8 */  0x78, 0x79, 0x25, 0xE4, 0xED, 0x45, 0x18, 0xA5,  // xy%..E..
            /* 09B0 */  0x71, 0x1E, 0x4D, 0x8B, 0x21, 0x30, 0xE7, 0xE1,  // q.M.!0..
            /* 09B8 */  0x26, 0x55, 0x1F, 0xA1, 0x4B, 0xDF, 0x5E, 0x5F,  // &U..K.^_
            /* 09C0 */  0x77, 0x22, 0xA5, 0x65, 0xBE, 0x0F, 0xB2, 0xCB,  // w".e....
            /* 09C8 */  0xDF, 0x77, 0x13, 0xA1, 0xB9, 0x18, 0x04, 0x8E,  // .w......
            /* 09D0 */  0xD6, 0x45, 0x8A, 0x81, 0x08, 0xBF, 0x42, 0x64,  // .E....Bd
            /* 09D8 */  0x7F, 0x12, 0x6E, 0xD7, 0xBC, 0xAB, 0x67, 0xAC,  // ..n...g.
            /* 09E0 */  0xC1, 0x18, 0x2D, 0x24, 0x09, 0x98, 0xD1, 0xCD,  // ..-$....
            /* 09E8 */  0xAE, 0x38, 0x1E, 0x09, 0x79, 0xC7, 0x42, 0xD4,  // .8..y.B.
            /* 09F0 */  0x46, 0xB2, 0xFF, 0x4D, 0x3A, 0xE8, 0x9C, 0x92,  // F..M:...
            /* 09F8 */  0xFD, 0x41, 0x00, 0x78, 0x84, 0x8A, 0x6F, 0x84,  // .A.x..o.
            /* 0A00 */  0xC3, 0x22, 0x0D, 0xEF, 0x3D, 0xD3, 0xDA, 0x0B,  // ."..=...
            /* 0A08 */  0xC0, 0x09, 0xE5, 0x1C, 0x9F, 0xE3, 0x25, 0xF2,  // ......%.
            /* 0A10 */  0x21, 0xB3, 0x42, 0x3D, 0x12, 0x07, 0x09, 0x0D,  // !.B=....
            /* 0A18 */  0x1F, 0x1A, 0x2E, 0x98, 0x48, 0x8B, 0xF0, 0xD6,  // ....H...
            /* 0A20 */  0xA1, 0x3E, 0xE2, 0x6A, 0xD2, 0x2E, 0x93, 0x39,  // .>.j...9
            /* 0A28 */  0x6A, 0x0E, 0x2B, 0x2B, 0x53, 0x1E               // j.++S.
        }
    })
    Method (DBDV, 0, NotSerialized)
    {
        Return (DBD0) /* \DBD0 */
    }

    Scope (\_SB.IETM)
    {
        Method (GDDV, 0, Serialized)
        {
            Return (DBDV ())
        }

        Method (IMOK, 1, NotSerialized)
        {
            Return (Arg0)
        }
    }
}

