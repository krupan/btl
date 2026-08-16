// NOTE: we can't name anything reg (because that's a SystemVerilog
// keyword) or register (because that's a C++ keyword and verilator
// complains)

package btl_regs;
    typedef enum {
        RW,
        RO,
        // PCIe spec uses RW1C for write-one-to-clear registers, so we
        // will too
        RW1C
    } FieldAttrib;

    typedef enum {
        FIELD,
        REG,
        ADDRMAP
    } ObjType;

    class Base;
        const string name;
        Base children[$];
        // this is so we don't have to cast to determine the type
        const ObjType my_type;
        btl::Address base_addr;
        const btl::Value offset;
        const btl::Value size_bytes;

        function new(string name);
            this.name = name;
        endfunction

        virtual function void reset();
            foreach(children[i]) begin
                children[i].reset();
            end
        endfunction
    endclass

    // named after SystemRDL things
    class Field extends Base;
        const btl::Value lsb;
        const btl::Value msb;
        const btl::Value size_bits;
        const btl::Value reset_value;
        const FieldAttrib sw_attrib;
        const FieldAttrib hw_attrib;
        btl::Value value;

        function new(string name,
                     FieldAttrib sw_attrib,
                     FieldAttrib hw_attrib,
                     btl::Value reset_value,
                     btl::Value msb,
                     btl::Value lsb);
            super.new(name);
            this.sw_attrib = sw_attrib;
            this.hw_attrib = hw_attrib;
            this.reset_value = reset_value;
            this.lsb = lsb;
            this.msb = msb;
            size_bits = msb - lsb + 1;
            reset();
            my_type = FIELD;
        endfunction

        function void reset();
            value = reset_value;
        endfunction

        function btl::Value read();
            return value;
        endfunction

        function void write(btl::Value val);
            case (sw_attrib)
                RO: begin
                    return;
                end
                RW1C: begin
                    for(int i = 0; i < size_bits[31:0]; i++) begin
                        if(val[i] == 1) begin
                            value[i] = 0;
                        end
                    end
                    return;
                end
                RW: begin
                    value = val;
                end
                default: begin
                    assert(0);
                end
            endcase
        endfunction

        function void hw_write(btl::Value val);
            case (hw_attrib)
                RO: begin
                    return;
                end
                RW: begin
                    value = val;
                end
                default: begin
                    assert(0);
                end
            endcase
        endfunction
    endclass : Field

    class Reg extends Base;

        function new(string name,
                     btl::Value size_bytes,
                     btl::Address offset);
            super.new(name);
            this.size_bytes = size_bytes;
            this.offset = offset;
            my_type = REG;
        endfunction

        function btl::Value read();
            btl::Value out;
            foreach(children[i]) begin
                Field field;
                btl::Value field_value;
                assert($cast(field, children[i]));
                field_value = field.read();
                for(btl::Value j = field.lsb; j <= field.msb; j++) begin
                    int field_ind = j[31:0] - field.lsb[31:0];
                    out[j[31:0]] = field_value[field_ind];
                end
            end
            return out;
        endfunction

        function void write(btl::Value val);
            foreach(children[i]) begin
                Field field;
                btl::Value val_slice;
                assert($cast(field, children[i]));
                for(int j = 0; j < field.size_bits[31:0]; j++) begin
                    val_slice[j] = val[j + field.lsb[31:0]];
                end
                field.write(val_slice);
            end
        endfunction
    endclass : Reg

    class AddrMap extends Base;
        function new(string name, btl::Value size_bytes, btl::Address base_addr);
            super.new(name);
            this.base_addr = base_addr;
            this.size_bytes = size_bytes;
            my_type = ADDRMAP;
        endfunction

        function bit addr_inside(btl::Address address);
            if(address < base_addr) begin
                return 0;
            end
            if(address > (base_addr + size_bytes - 1)) begin
                return 0;
            end
            return 1;
        endfunction

        function bit get_reg_by_addr(btl::Address addr,
                                     ref btl_regs::Reg the_reg);
            if(!addr_inside(addr)) begin
                return 0;
            end
            foreach(children[i]) begin
                AddrMap addrmap;
                case(children[i].my_type)
                    REG: begin
                        btl::Address reg_addr = base_addr + children[i].offset;
                        if(addr == reg_addr) begin
                            assert($cast(the_reg, children[i]));
                            return 1;
                        end
                    end
                    ADDRMAP: begin
                        assert($cast(addrmap, children[i]));
                        if(addrmap.get_reg_by_addr(addr, the_reg)) begin
                            return 1;
                        end
                    end
                    default: begin
                        $display("my_type: %s, children[%0d].my_type: %s",
                        my_type.name, i, children[i].my_type.name);
                        assert(0);
                    end
                endcase
            end
            return 0;
        endfunction

        function bit reg_write(btl::Address addr, btl::Value val);
            Reg the_reg;
            if(get_reg_by_addr(addr, the_reg)) begin
                the_reg.write(val);
                return 1;
            end
            return 0;
        endfunction

        function bit reg_read(btl::Address addr, output btl::Value val);
            Reg the_reg;
            if(get_reg_by_addr(addr, the_reg)) begin
                val = the_reg.read();
                return 1;
            end
            return 0;
        endfunction
    endclass : AddrMap
endpackage : btl_regs
