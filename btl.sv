// B Testbench Library (much simpler than UVM)
package btl;

    interface class Transaction;
    endclass

    interface class Component;
        pure virtual task run();

        // run should look something like this:
        //
        // task run();
        //     forever begin
        //         do_something()
        //     end
        // endtask
    endclass

    typedef mailbox #(Transaction) TxnMailbox;

    interface class Subscriber;
        pure virtual function void put(Transaction txn);

        // suggested class member
        //
        // btl::Subscriber::TxnMailbox txns_in;

        // suggested constructor
        //
        // function new();
        //     txns_in = new();
        // endfunction


        // suggested implementation of put
        //
        // function void put(Txn txn);
        //     txns_in.push_back(txn);
        // endfunction
    endclass

    typedef Subscriber SubscriberList[$];

    interface class Producer;
        pure virtual function void add_subscriber(Subscriber subscriber);

        // suggested class member
        //
        // btl::Producer::SubscriberList subscribers;

        // suggested implementation of subscribe
        //
        // function void add_subscriber(btl::TxnSubscriber subscriber);
        //     subscribers.push_back(subscriber);
        // endfunction
    endclass

    typedef enum {
        RW,
        RO,
        // PCIe spec uses RW1C for write-one-to-clear registers, so we
        // will too
        RW1C
    } FieldAttrib;

    // named after SystemRDL things
    class Field;
        int unsigned lsb;
        int unsigned size_bits;
        string name;
        const longint unsigned reset_value;
        FieldAttrib attrib;
        longint unsigned value;

        function new(int unsigned lsb_in,
                     int unsigned size_bits_in,
                     string name_in,
                     longint unsigned reset_value_in,
                     FieldAttrib attrib_in);
            lsb = lsb_in;
            size_bits = size_bits_in;
            name = name_in;
            reset_value = reset_value_in;
            attrib = attrib_in;
            reset();
        endfunction

        function void reset();
            value = reset_value;
        endfunction

        function int unsigned msb();
            return lsb + (size_bits - 1);
        endfunction

        function longint unsigned read();
            return value;
        endfunction

        function void write(longint unsigned val);
            case (attrib)
                RO: begin
                    return;
                end
                RW1C: begin
                    value = 0;
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
    
    typedef Field Fields[longint unsigned];

    class Reg;
        string name;
        longint unsigned offset;
        int unsigned size_bytes;
        Fields fields;

        function new(string name_in,
                     longint unsigned offset_in,
                     int unsigned size_bytes_in);
            name = name_in;
            offset = offset_in;
            size_bytes = size_bytes_in;
        endfunction

        function void add_fields(Fields fields_in);
            fields = fields_in;
        endfunction

        function longint unsigned read();
            longint unsigned out;
            foreach(fields[i]) begin
                Field f = fields[i];
                out[f.msb:f.lsb] = f.read();
            end
            return out;
        endfunction

        function void write(longint unsigned val);
            foreach(fields[i]) begin
                Field f = fields[i];
                f.write(val[f.msb:f.lsb]);
            end
        endfunction
    endclass : Reg

    // index is a register offset
    typedef Reg Regs[longint unsigned];

    class AddrMap;
        longint unsigned base_addr;
        int unsigned size_bytes;
        string name;
        Regs regs;

        function bit addr_inside(longint unsigned address);
            if(address > base_addr) begin
                return 0;
            end
            if(address < (base_addr + (size_bytes-1))) begin
                return 0;
            end
            return 1;
        endfunction

        function bit reg_write(longint unsigned addr,
                               longint unsigned value);
            if(!regs.exists(addr)) begin
                return 0;
            end
            regs[addr].write(value);
        endfunction

        function bit reg_read(longint unsigned addr,
                              output longint unsigned value);
            if(!regs.exists(addr)) begin
                return 0;
            end
            return regs[addr].read();
        endfunction

    endclass : AddrMap
endpackage
