package goldengate.tests.core

import chisel3._
import chisel3.util._
import midas.core.PipeChannel
import org.chipsalliance.cde.config.Parameters
import org.scalatest.flatspec.AnyFlatSpec
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import scala.sys.process._

/** The actual Golden Gate channel implementation, including its reset token,
  * paces a target actor and a bridge actor. The target records which replay
  * epoch issued each cycle; the bridge parks the wake cycle before consuming.
  */
class LrcChannelFenceHarness(outputLatency: Int, ordinaryFence: Boolean = false,
  ordinaryResume: Boolean = false) extends Module {
  implicit val p: Parameters = Parameters.empty
  val io = IO(new Bundle {
    val resume = Input(Bool())
    val parked = Output(Bool())
    val targetNextCycle = Output(UInt(16.W))
    val nextSeen = Output(Bool())
    val nextEpoch = Output(UInt(8.W))
  })
  val fromHost = Module(new PipeChannel(UInt(8.W), 1))
  val physical = Module(new PipeChannel(UInt(24.W), outputLatency))
  val legacy = Module(new PipeChannel(UInt(16.W), 1))
  val cycle = RegInit(1.U(16.W))
  val targetFire = fromHost.io.out.valid && physical.io.in.ready && legacy.io.in.ready
  fromHost.io.out.ready := targetFire
  physical.io.in.valid := targetFire
  physical.io.in.bits := Cat(fromHost.io.out.bits, cycle)
  legacy.io.in.valid := targetFire
  legacy.io.in.bits := cycle
  when(targetFire) { cycle := cycle + 1.U }

  val released = RegInit(false.B)
  val parked = RegInit(false.B)
  val physicalCycle = physical.io.out.bits(15, 0)
  val fenceCycle = if (ordinaryFence) legacy.io.out.bits else physicalCycle
  val fence = physical.io.out.valid && legacy.io.out.valid && fenceCycle === 3.U && !released
  when(fence) { parked := true.B }
  when(io.resume && parked) { released := true.B }
  val bridgeFire = physical.io.out.valid && legacy.io.out.valid &&
    fromHost.io.in.ready && !fence
  physical.io.out.ready := bridgeFire
  legacy.io.out.ready := bridgeFire
  fromHost.io.in.valid := bridgeFire
  val firstRelease = RegInit(true.B)
  when(bridgeFire && released) { firstRelease := false.B }
  fromHost.io.in.bits := Mux(released && !(ordinaryResume.B && firstRelease), 1.U, 0.U)
  val nextSeen = RegInit(false.B)
  val nextEpoch = Reg(UInt(8.W))
  when(bridgeFire && physicalCycle === (if (ordinaryFence) 5 else 4).U) {
    nextSeen := true.B
    nextEpoch := physical.io.out.bits(23, 16)
  }
  io.parked := parked
  io.targetNextCycle := cycle
  io.nextSeen := nextSeen
  io.nextEpoch := nextEpoch
}

class LrcChannelFenceSpec extends AnyFlatSpec {
  behavior of "Golden Gate channels at a native LRC wake fence"

  private def check(outputLatency: Int, ordinaryFence: Boolean = false,
    ordinaryResume: Boolean = false): Unit = {
    val dir = Files.createTempDirectory("lrc-channel-fence-")
    (new chisel3.stage.ChiselStage).emitVerilog(new LrcChannelFenceHarness(outputLatency,
      ordinaryFence, ordinaryResume),
      Array("--target-dir", dir.toString))
    val expectedNext = if (outputLatency == 0 && !ordinaryFence) 4 else 5
    val expectedEpoch = if (outputLatency == 0 && !ordinaryResume) 1 else 0
    val main = s"""#include "VLrcChannelFenceHarness.h"
      |#include "verilated.h"
      |#include <cassert>
      |int main() {
      |  VLrcChannelFenceHarness d;
      |  auto step = [&]() { d.clock=0; d.eval(); d.clock=1; d.eval(); };
      |  d.reset=1; d.io_resume=0; for(int i=0;i<5;++i)step(); d.reset=0;
      |  for(int i=0;i<1000 && !d.io_parked;++i)step(); assert(d.io_parked);
      |  for(int i=0;i<30;++i)step();
      |  assert(d.io_targetNextCycle == $expectedNext);
      |  d.io_resume=1;
      |  for(int i=0;i<1000 && !d.io_nextSeen;++i)step();
      |  assert(d.io_nextSeen); assert(d.io_nextEpoch == $expectedEpoch);
      |  return 0;
      |}
      |""".stripMargin
    Files.write(dir.resolve("main.cc"), main.getBytes(StandardCharsets.UTF_8))
    val build = Seq("verilator", "--cc", "--exe", "--build", "-Wno-fatal", "--top-module",
      "LrcChannelFenceHarness", "LrcChannelFenceHarness.v", "main.cc")
    assert(Process(build, dir.toFile).! == 0)
    assert(Process(Seq(dir.resolve("obj_dir/VLrcChannelFenceHarness").toString), dir.toFile).! == 0)
  }

  it should "prevent old-epoch C+1 execution with latency-zero physical snapshots" in { check(0) }
  it should "expose the extra old-epoch cycle with the legacy latency-one snapshot" in { check(1) }
  it should "hold the ordinary boundary's following raw snapshot until the native epoch is installed" in {
    check(0, ordinaryFence = true)
  }
  it should "retain the ordinary resume delay by releasing its parked token with prior inputs" in {
    check(0, ordinaryFence = true, ordinaryResume = true)
  }
}
