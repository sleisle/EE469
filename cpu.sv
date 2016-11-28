`timescale 1 ps/1 ps

module cpu (clk, reset);
	input logic clk, reset;

	logic [31:0] instruction;
	logic [9:0] flags;
	logic [2:0] ALUOp;
	logic [10:0] opcode;
	logic [4:0] Rd, Rn, Rm;
	logic [8:0] DT_Address9;
	logic [18:0] CondAddr19;
	logic [11:0] ALU_Imm12;
	
	logic [63:0] readData1, readData2, writeDataRegister, writeDataMem, readDataMem;
	
	logic [4:0] reg2LocMuxOut;
	logic [63:0] aluInput2MuxOut, ADDImmMuxOut, dataMemOutputMuxOut, ALUSrcMuxOutput, aluOutput, DAddr9SEOut, ALU_Imm12ZEOut, MemToRegMuxOut, BLMuxOut;
	logic aluNegative, aluZero, aluOverflow, aluCarry_out, dataMemReadEn, BLTTaken;
	
	
	logic [63:0] address; 
	logic [18:0] Imm19;
	logic [25:0] Imm26;
	logic [63:0] Imm19Extended, Imm26Extended; 
	logic [63:0] muxToShiftLeft, shiftLeftToAdder, adderToMux1, adderToMux0, muxBrTakenToMuxBr, muxBrToPC; 
	logic cOut0, cOut1, overflow0, overflow1;
	
	// PIPELINE LOGICS //
	logic [31:0] ifInstruction, rfInstruction, exInstruction, dmInstruction, wbInstruction;
	
	assign Imm19 = instruction[23:5];
	assign Imm26 = instruction[25:0];
	assign opcode = instruction[31:21];
	assign Rn = instruction[9:5];
	assign Rm = instruction[20:16];
	assign DT_Address9 = instruction[20:12];
	assign CondAddr19 = instruction[23:5];
	assign ALU_Imm12 = instruction[21:10];
	
	// B.LT XOR
	xor #50 blt (BLTTaken, aluNegativePrev, aluOverflowPrev);
	
	// Flags = reg2loc,ALUSrc,MemToReg,RegWrite,MemWrite,BrTaken,UnCondBr,LBranch,IsBr,AddImm;
	always_comb begin
		casez (opcode)
			11'b000101?????: begin // B
				flags = 10'b???001100?;
				ALUOp = 3'b???;
				dataMemReadEn = 1'b0;
				Rd = instruction[4:0];
			end
			
			11'b100101?????: begin // BL
				flags = 10'b???101110?;
				ALUOp = 3'b???;
				dataMemReadEn = 1'b0;
				Rd = 5'b11110;
			end
			
			11'b01010100???: begin // B.LT
				flags = {5'b???00, BLTTaken, 4'b0?0?};
				ALUOp = 3'b???;
				dataMemReadEn = 1'b0;
				Rd = instruction[4:0];
			end
			
			11'b10110100???: begin // CBZ
				flags = {5'b00?00, aluZero, 4'b0?0?};
				ALUOp = 3'b000;
				dataMemReadEn = 1'b0;
				Rd = instruction[4:0];
			end
			
			11'b10101011000: begin // ADDS
				flags = 10'b100100?00?;
				ALUOp = 3'b010;
				dataMemReadEn = 1'b0;
				Rd = instruction[4:0];
			end
			
			11'b11101011000: begin // SUBS
				flags = 10'b100100?00?;
				ALUOp = 3'b011;
				dataMemReadEn = 1'b0;
				Rd = instruction[4:0];
			end
			
			11'b11010110000: begin // BR
				flags = 10'b0??00???1?;
				ALUOp = 3'b???;
				dataMemReadEn = 1'b0;
				Rd = instruction[4:0];
			end
			
			11'b1001000100?: begin // ADDI
				flags = 10'b?10100?001;
				ALUOp = 3'b010;
				dataMemReadEn = 1'b0;
				Rd = instruction[4:0];
			end
			
			11'b11111000010: begin // LDUR
				flags = 10'b?11100?000;
				ALUOp = 3'b010;
				dataMemReadEn = 1'b1;
				Rd = instruction[4:0];
			end
			
			11'b11111000000: begin // STUR
				flags = 10'b01?010??00;
				ALUOp = 3'b010;
				dataMemReadEn = 1'b0;
				Rd = instruction[4:0];
			end			
			
			default: begin
				flags = {3'b?, 1'b0, 1'b0, 5'b?};
				ALUOp = 3'b???;
				dataMemReadEn = 1'b0;
				Rd = instruction[4:0];
			end
		endcase
	end
	
	// INSTRUCTION FETCH //
	
	pc programCounter (.writeEnable(1'b1), .writeData(muxBrToPC), .dataOut(address), .reset(reset), .clk(clk));
	instructmem insMem(.address(address), .instruction(instruction), .clk(clk));
	
	register32Bit rfInstructionRegister (.writeEnable(1'b1), .writeData(instruction), .dataOut(ifInstruction), .reset(reset), .clk(clk));
	
	signExtend19 SE1 (.in(Imm19), .out(Imm19Extended));
	signExtend26 SE2(.in(Imm26), .out(Imm26Extended));
	shiftLeft SL (.in(muxToShiftLeft), .out(shiftLeftToAdder));
	
	mux64x2_1 brTaken (.zero(adderToMux0), .one(adderToMux1), .control(flags[4]), .out(muxBrTakenToMuxBr));
	mux64x2_1 isBr (.zero(muxBrTakenToMuxBr), .one(readData2), .control(flags[1]), .out(muxBrToPC));
	mux64x2_1 uncondBr (.zero(Imm19Extended), .one(Imm26Extended), .control(flags[3]), .out(muxToShiftLeft));
	
	// REGISTER FETCH //
	
	regfile registerFile (.ReadData1(readData1), .ReadData2(readData2), .WriteData(BLMuxOut), .ReadRegister1(Rn), .ReadRegister2(reg2LocMuxOut), .WriteRegister(Rd), .RegWrite(flags[6]), .clk(clk));
	
	register32Bit rfInstructionRegister (.writeEnable(1'b1), .writeData(ifInstruction), .dataOut(rfInstruction), .reset(reset), .clk(clk));
	
	signExtend9 se9 (.in(DT_Address9), .out(DAddr9SEOut));
	zeroExtend ze (.in(ALU_Imm12), .out(ALU_Imm12ZEOut));
	
	mux64x2_1 ALUSrcMux (.zero(readData2), .one(ADDImmMuxOut), .control(flags[8]), .out(ALUSrcMuxOutput));
	mux64x2_1 BLMux (.zero(MemToRegMuxOut), .one(adderToMux0), .control(flags[2]), .out(BLMuxOut));
	mux64x2_1 ADDImmMux (.zero(DAddr9SEOut), .one(ALU_Imm12ZEOut), .control(flags[0]), .out(ADDImmMuxOut));
	
	genvar i;
	generate
		for (i = 0; i < 5; i++) begin: regMux
			mux2_1 m (.a(Rm[i]), .b(Rd[i]), .x(flags[9]), .out(reg2LocMuxOut[i]));
		end
	
	endgenerate	
	
	// EXECUTE //

	alu arithmeticLogic (.A(readData1), .B(ALUSrcMuxOutput), .cntrl(ALUOp), .result(aluOutput), .negative(aluNegative), .zero(aluZero), .overflow(aluOverflow), .carry_out(aluCarryOut));
	D_FF aluNegSave (.q(aluNegativePrev), .d(aluNegative), .reset(reset), .clk(clk));
	D_FF aluOvSave (.q(aluOverflowPrev), .d(aluOverflow), .reset(reset), .clk(clk));
	
	register32Bit rfInstructionRegister (.writeEnable(1'b1), .writeData(rfInstruction), .dataOut(exInstruction), .reset(reset), .clk(clk));
	
	// DATA MEMORY //
	
	datamem dataMemory (.address(aluOutput), .write_enable(flags[5]), .read_enable(dataMemReadEn), .write_data(readData2), .clk(clk), .xfer_size(4'b1000), .read_data(readDataMem));
	fastAdder FA0 (.A(address), .B(64'h0000000000000004), .cntrl(1'b0), .result(adderToMux0), .cOut(cOut0), .overflow(overflow0)); // control is 0 to do addition
	fastAdder FA1 (.A(shiftLeftToAdder), .B(address), .cntrl(1'b0), .result(adderToMux1), .cOut(cOut1), .overflow(overflow1)); // control is 0 to do addition

	register32Bit rfInstructionRegister (.writeEnable(1'b1), .writeData(exInstruction), .dataOut(dmInstruction), .reset(reset), .clk(clk));
	
	mux64x2_1 MemToRegMux (.zero(aluOutput), .one(readDataMem), .control(flags[7]), .out(MemToRegMuxOut));
	
	// WRITE BACK //
	register32Bit rfInstructionRegister (.writeEnable(1'b1), .writeData(dmInstruction), .dataOut(wbInstruction), .reset(reset), .clk(clk));
	
endmodule

module cpuTestbench ();

	parameter ClockDelay = 10000;
	parameter loopEnd = 100;

	logic clk;
	logic reset;
	cpu dut (.clk, .reset);
	
	integer i;
	

	// Force %t's to print in a nice format.
	initial $timeformat(-9, 2, " ns", 10);

	initial begin // Set up the clock
		clk <= 0;
		forever #(ClockDelay/2) clk <= ~clk;
	end

	initial begin
		reset <= 1; @(posedge clk);
		reset <= 0; @(posedge clk);
		
		for (i=0; i<loopEnd; i++) begin
			@(posedge clk);
		end
		
		$stop;
	end

endmodule


