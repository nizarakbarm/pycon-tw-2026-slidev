source_filename = "test.py"
; ModuleID = "test.py"
target triple = "bpf"
target datalayout = "e-m:e-p:64:64-i64:64-i128:128-n32:64-S128"

declare i8* @"llvm.bpf.passthrough.p0.p0"(i32 %".1", i8* %".2") nounwind

@"LICENSE" = dso_local global [4 x i8] [i8 71, i8 80, i8 76, i8 0], section "license", align 1
@"stats" = dso_local global {ptr, ptr, ptr, ptr} zeroinitializer, section ".maps", align 8, !dbg !27
define dso_local i64 @"track_syscalls"(ptr captures(none) %".1") noinline nounwind section "tracepoint/syscalls/sys_enter_read"
{
entry:
  %"process_id" = alloca i64, align 8
  %"s" = alloca i64*
  %"s_tmp" = alloca {i64, i64, i64}
  %"new_stats" = alloca {i64, i64, i64}
  %".3" = inttoptr i64 14 to i64 ()*
  %".4" = call i64 %".3"()
  %".5" = and i64 %".4", 4294967295
  store i64 %".5", i64* %"process_id"
  %".7" = inttoptr i64 1 to i64* (ptr, ptr)*
  %".8" = call i64* %".7"({ptr, ptr, ptr, ptr}* @"stats", i64* %"process_id")
  store i64* %".8", i64** %"s"
  %".10" = load i64*, i64** %"s"
  %".11" = icmp ne i64* %".10", null
  br i1 %".11", label %"if.then", label %"if.else"
if.then:
  %".13" = getelementptr inbounds i64*, i64** %"s", i32 0, i32 0
  %".14" = load i64*, i64** %"s"
  %".15" = icmp ne i64* %".14", null
  br i1 %".15", label %"field_syscall_count_not_null", label %"field_syscall_count_merge"
if.end:
  ret i64 0
if.else:
  store {i64, i64, i64} zeroinitializer, {i64, i64, i64}* %"new_stats"
  %".28" = getelementptr inbounds {i64, i64, i64}, {i64, i64, i64}* %"new_stats", i32 0, i32 0
  store i64 1, i64* %".28"
  %".30" = getelementptr inbounds {i64, i64, i64}, {i64, i64, i64}* %"new_stats", i32 0, i32 1
  store i64 0, i64* %".30"
  %".32" = getelementptr inbounds {i64, i64, i64}, {i64, i64, i64}* %"new_stats", i32 0, i32 2
  store i64 0, i64* %".32"
  %".34" = inttoptr i64 2 to i64 (ptr, ptr, ptr, i64)*
  %".35" = call i64 %".34"({ptr, ptr, ptr, ptr}* @"stats", i64* %"process_id", {i64, i64, i64}* %"new_stats", i64 0)
  br label %"if.end"
field_syscall_count_not_null:
  %".17" = bitcast i64* %".14" to {i64, i64, i64}*
  %".18" = getelementptr inbounds {i64, i64, i64}, {i64, i64, i64}* %".17", i32 0, i32 0
  %".19" = load i64, i64* %".18"
  br label %"field_syscall_count_merge"
field_syscall_count_merge:
  %"field_syscall_count_result" = phi  i64 [0, %"if.then"], [%".19", %"field_syscall_count_not_null"]
  %".21" = add i64 %"field_syscall_count_result", 1
  store i64 %".21", i64* %".13"
  %".23" = load i64*, i64** %"s"
  %".24" = inttoptr i64 2 to i64 (ptr, ptr, ptr, i64)*
  %".25" = call i64 %".24"({ptr, ptr, ptr, ptr}* @"stats", i64* %"process_id", i64* %".23", i64 0)
  br label %"if.end"
}

@"llvm.compiler.used" = appending global [3 x ptr] [[4 x i8]* @"LICENSE", {ptr, ptr, ptr, ptr}* @"stats", i64 (ptr)* @"track_syscalls"], section "llvm.metadata"
!llvm.dbg.cu = !{ !1 }
!llvm.module.flags = !{ !29, !30, !31, !32 }
!llvm.ident = !{ !33 }
!0 = !DIFile(directory: "", filename: "test.py")
!1 = distinct !DICompileUnit(emissionKind: 1, file: !0, isOptimized: true, language: 29, nameTableKind: 0, producer: "PythonBPF v0.2.0", runtimeVersion: 0, splitDebugInlining: false)
!2 = !DIBasicType(encoding: 7, name: "unsigned int", size: 32)
!3 = !DISubrange(count: 1)
!4 = !{ !3 }
!5 = !DICompositeType(baseType: !2, elements: !4, size: 32, tag: 1)
!6 = !DIDerivedType(baseType: !5, size: 64, tag: 15)
!7 = !DIDerivedType(baseType: !2, size: 64, tag: 15)
!8 = !DIBasicType(encoding: 7, name: "unsigned long long", size: 64)
!9 = !DIDerivedType(baseType: !8, file: !0, name: "syscall_count", offset: 8, size: 64, tag: 13)
!10 = !DIDerivedType(baseType: !8, file: !0, name: "total_time", offset: 8, size: 64, tag: 13)
!11 = !DIDerivedType(baseType: !8, file: !0, name: "max_latency", offset: 8, size: 64, tag: 13)
!12 = !{ !9, !10, !11 }
!13 = distinct !DICompositeType(elements: !12, file: !0, size: 192, tag: 19)
!14 = !DIDerivedType(baseType: !13, size: 64, tag: 15)
!15 = !DIDerivedType(baseType: !7, file: !0, name: "key", offset: 0, size: 64, tag: 13)
!16 = !DIDerivedType(baseType: !14, file: !0, name: "value", offset: 64, size: 64, tag: 13)
!17 = !DIDerivedType(baseType: !6, file: !0, name: "type", offset: 128, size: 64, tag: 13)
!18 = !DISubrange(count: 1024)
!19 = !{ !18 }
!20 = !DICompositeType(baseType: !2, elements: !19, size: 32768, tag: 1)
!21 = !DIDerivedType(baseType: !20, size: 64, tag: 15)
!22 = !DIDerivedType(baseType: !21, file: !0, name: "max_entries", offset: 192, size: 64, tag: 13)
!23 = !{ !15, !16, !17, !22 }
!24 = distinct !DICompositeType(elements: !23, file: !0, size: 256, tag: 19)
!25 = distinct !DIGlobalVariable(file: !0, isDefinition: true, isLocal: false, name: "stats", scope: !1, type: !24)
!26 = !DIExpression()
!27 = !DIGlobalVariableExpression(expr: !26, var: !25)
!28 = !DIBasicType(encoding: 5, name: "long", size: 64)
!29 = !{ i32 1, !"wchar_size", i32 4 }
!30 = !{ i32 7, !"frame-pointer", i32 2 }
!31 = !{ i32 2, !"Debug Info Version", i32 3 }
!32 = !{ i32 7, !"Dwarf Version", i32 5 }
!33 = !{ !"PythonBPF v0.2.0" }
