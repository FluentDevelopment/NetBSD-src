/*	$NetBSD: cpufunc.S,v 1.45 2019/09/07 18:56:01 maxv Exp $	*/

/*
 * Copyright (c) 1998, 2007, 2008 The NetBSD Foundation, Inc.
 * All rights reserved.
 *
 * This code is derived from software contributed to The NetBSD Foundation
 * by Charles M. Hannum, and by Andrew Doran.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE NETBSD FOUNDATION, INC. AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include <sys/errno.h>

#include <machine/asm.h>
#include <machine/frameasm.h>
#include <machine/specialreg.h>
#include <machine/segments.h>

#include "opt_xen.h"
#include "opt_svs.h"

#include "assym.h"

/* Small and slow, so align less. */
#undef _ALIGN_TEXT
#define	_ALIGN_TEXT	.align 8

ENTRY(x86_lfence)
	lfence
	ret
END(x86_lfence)

ENTRY(x86_sfence)
	sfence
	ret
END(x86_sfence)

ENTRY(x86_mfence)
	mfence
	ret
END(x86_mfence)

#ifndef XENPV
ENTRY(invlpg)
#ifdef SVS
	movb	_C_LABEL(svs_pcid),%al
	testb	%al,%al
	jz	1f
	pushq	%rdi
	pushq	$PMAP_PCID_USER
	movq	$INVPCID_ADDRESS,%rax
	invpcid	(%rsp),%rax
	addq	$16,%rsp
1:	/* FALLTHROUGH */
#endif
	invlpg	(%rdi)
	ret
END(invlpg)

ENTRY(lgdt)
	/* Reload the descriptor table. */
	movq	%rdi,%rax
	lgdt	(%rax)
	/* Flush the prefetch queue. */
	jmp	1f
	nop
1:	jmp	_C_LABEL(lgdt_finish)
END(lgdt)

ENTRY(lidt)
	lidt	(%rdi)
	ret
END(lidt)

ENTRY(lldt)
	cmpl	%edi, CPUVAR(CURLDT)
	jne	1f
	ret
1:
	movl	%edi, CPUVAR(CURLDT)
	lldt	%di
	ret
END(lldt)

ENTRY(ltr)
	ltr	%di
	ret
END(ltr)

ENTRY(tlbflushg)
	movq	%cr4, %rax
	testq	$CR4_PGE, %rax
	jz	tlbflush
	movq	%rax, %rdx
	andq	$~CR4_PGE, %rdx
	movq	%rdx, %cr4
	movq	%rax, %cr4
	ret
END(tlbflushg)

ENTRY(tlbflush)
#ifdef SVS
	movb	_C_LABEL(svs_pcid),%al
	testb	%al,%al
	jz	1f
	xorq	%rax,%rax
	pushq	%rax
	pushq	%rax
	movq	$INVPCID_ALL_NONGLOBAL,%rax
	invpcid	(%rsp),%rax
	addq	$16,%rsp
	ret
#endif
1:	movq	%cr3, %rax
	movq	%rax, %cr3
	ret
END(tlbflush)

ENTRY(wbinvd)
	wbinvd
	ret
END(wbinvd)

ENTRY(setusergs)
	CLI(ax)
	swapgs
	movw	%di, %gs
	swapgs
	STI(ax)
	ret
END(setusergs)

ENTRY(x86_read_flags)
	pushfq
	popq	%rax
	ret
END(x86_read_flags)

STRONG_ALIAS(x86_read_psl,x86_read_flags)

ENTRY(x86_write_flags)
	pushq	%rdi
	popfq
	ret
END(x86_write_flags)

STRONG_ALIAS(x86_write_psl,x86_write_flags)

ENTRY(tsc_get_timecount)
	movq	CPUVAR(CURLWP), %rcx
1:
	movq	L_NCSW(%rcx), %rdi
	rdtsc
	addl	CPUVAR(CC_SKEW), %eax
	cmpq	%rdi, L_NCSW(%rcx)
	jne	2f
	ret
2:
	jmp	1b
END(tsc_get_timecount)
#endif /* !XENPV */

ENTRY(rdmsr_safe)
	movq	CPUVAR(CURLWP), %r8
	movq	L_PCB(%r8), %r8
	movq	$_C_LABEL(msr_onfault), PCB_ONFAULT(%r8)

	movl	%edi, %ecx
	rdmsr
	salq	$32, %rdx
	movl	%eax, %eax	/* zero-extend %eax -> %rax */
	orq	%rdx, %rax
	movq	%rax, (%rsi)

	xorq	%rax, %rax
	movq	%rax, PCB_ONFAULT(%r8)
	ret
END(rdmsr_safe)

ENTRY(msr_onfault)
	movq	CPUVAR(CURLWP), %r8
	movq	L_PCB(%r8), %r8
	movq	$0, PCB_ONFAULT(%r8)
	movl	$EFAULT, %eax
	ret
END(msr_onfault)

ENTRY(cpu_counter)
	xorq	%rax, %rax
	rdtsc
	shlq	$32, %rdx
	orq	%rdx, %rax
	addq	CPUVAR(CC_SKEW), %rax
	ret
END(cpu_counter)

ENTRY(cpu_counter32)
	rdtsc
	addl	CPUVAR(CC_SKEW), %eax
	ret
END(cpu_counter32)

ENTRY(breakpoint)
	pushq	%rbp
	movq	%rsp, %rbp
	int	$0x03		/* paranoid, not 'int3' */
	leave
	ret
END(breakpoint)

ENTRY(x86_curcpu)
	movq	%gs:(CPU_INFO_SELF), %rax
	ret
END(x86_curcpu)

ENTRY(x86_curlwp)
	movq	%gs:(CPU_INFO_CURLWP), %rax
	ret
END(x86_curlwp)

ENTRY(cpu_set_curpri)
	movl	%edi, %gs:(CPU_INFO_CURPRIORITY)
	ret
END(cpu_set_curpri)

ENTRY(__byte_swap_u32_variable)
	movl	%edi, %eax
	bswapl	%eax
	ret
END(__byte_swap_u32_variable)

ENTRY(__byte_swap_u16_variable)
	movl	%edi, %eax
	xchgb	%al, %ah
	ret
END(__byte_swap_u16_variable)

/*
 * Reload segments after a GDT change.
 */
ENTRY(lgdt_finish)
	movl	$GSEL(GDATA_SEL, SEL_KPL),%eax
	movl	%eax,%ds
	movl	%eax,%es
	movl	%eax,%ss
	jmp	_C_LABEL(x86_flush)
END(lgdt_finish)

/*
 * Flush instruction pipelines by doing an intersegment (far) return.
 */
ENTRY(x86_flush)
	popq	%rax
	pushq	$GSEL(GCODE_SEL, SEL_KPL)
	pushq	%rax
	lretq
END(x86_flush)

/* Waits - set up stack frame. */
ENTRY(x86_hlt)
	pushq	%rbp
	movq	%rsp, %rbp
	hlt
	leave
	ret
END(x86_hlt)

/* Waits - set up stack frame. */
ENTRY(x86_stihlt)
	pushq	%rbp
	movq	%rsp, %rbp
	sti
	hlt
	leave
	ret
END(x86_stihlt)

ENTRY(x86_monitor)
	movq	%rdi, %rax
	movq	%rsi, %rcx
	monitor	%rax, %rcx, %rdx
	ret
END(x86_monitor)

/* Waits - set up stack frame. */
ENTRY(x86_mwait)
	pushq	%rbp
	movq	%rsp, %rbp
	movq	%rdi, %rax
	movq	%rsi, %rcx
	mwait	%rax, %rcx
	leave
	ret
END(x86_mwait)

ENTRY(fnsave)
	fnsave	(%rdi)
	ret
END(fnsave)

ENTRY(frstor)
	frstor	(%rdi)
	ret
END(frstor)

ENTRY(stts)
	movq	%cr0, %rax
	orq	$CR0_TS, %rax
	movq	%rax, %cr0
	ret
END(stts)

ENTRY(fxsave)
	fxsave	(%rdi)
	ret
END(fxsave)

ENTRY(fxrstor)
	fxrstor	(%rdi)
	ret
END(fxrstor)

ENTRY(fldummy)
	ffree	%st(7)
	fldz
	ret
END(fldummy)

ENTRY(xsave)
	movq	%rsi, %rax
	movq	%rsi, %rdx
	shrq	$32, %rdx
	xsave	(%rdi)
	ret
END(xsave)

ENTRY(xsaveopt)
	movq	%rsi, %rax
	movq	%rsi, %rdx
	shrq	$32, %rdx
	xsaveopt	(%rdi)
	ret
END(xsaveopt)

ENTRY(xrstor)
	movq	%rsi, %rax
	movq	%rsi, %rdx
	shrq	$32, %rdx
	xrstor	(%rdi)
	ret
END(xrstor)

ENTRY(inb)
	movq	%rdi, %rdx
	xorq	%rax, %rax
	inb	%dx, %al
	ret
END(inb)

ENTRY(insb)
	movl	%edx, %ecx
	movl	%edi, %edx
	movq	%rsi, %rdi
	rep
	insb
	ret
END(insb)

ENTRY(inw)
	movq	%rdi, %rdx
	xorq	%rax, %rax
	inw	%dx, %ax
	ret
END(inw)

ENTRY(insw)
	movl	%edx, %ecx
	movl	%edi, %edx
	movq	%rsi, %rdi
	rep
	insw
	ret
END(insw)

ENTRY(inl)
	movq	%rdi, %rdx
	xorq	%rax, %rax
	inl	%dx, %eax
	ret
END(inl)

ENTRY(insl)
	movl	%edx, %ecx
	movl	%edi, %edx
	movq	%rsi, %rdi
	rep
	insl
	ret
END(insl)

ENTRY(outb)
	movq	%rdi, %rdx
	movq	%rsi, %rax
	outb	%al, %dx
	ret
END(outb)

ENTRY(outsb)
	movl	%edx, %ecx
	movl	%edi, %edx
	rep
	outsb
	ret
END(outsb)

ENTRY(outw)
	movq	%rdi, %rdx
	movq	%rsi, %rax
	outw	%ax, %dx
	ret
END(outw)

ENTRY(outsw)
	movl	%edx, %ecx
	movl	%edi, %edx
	rep
	outsw
	ret
END(outsw)

ENTRY(outl)
	movq	%rdi, %rdx
	movq	%rsi, %rax
	outl	%eax, %dx
	ret
END(outl)

ENTRY(outsl)
	movl	%edx, %ecx
	movl	%edi, %edx
	rep
	outsl
	ret
END(outsl)
