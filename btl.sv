// B Testbench Library (much simpler than UVM)
package btl;
    // request (REQ) and response (RSP) types
    typedef enum {
        READ_REQ,
        WRITE_REQ,
        INCOMPLETE_RSP,
        RSP
    } BaseTxnType;

    typedef byte unsigned ByteQ[$];
    typedef int ID;

    let max(a,b) = (a > b) ? a : b;
    let min(a,b) = (a < b) ? a : b;

    class Transaction;
        BaseTxnType base_type;
        ID id;
        ID requester_id;
        string name;
        ByteQ data;
        int unsigned data_size; // number of bytes

        // this is for INCOMPLETE_RSP transactions that need multiple
        // responses (probably of a lower-level transaction type).
        // Use requester IDs for the keys to this associative array
        Transaction missing_responses[ID];

        function new(BaseTxnType type_in);
            base_type = type_in;
            name = "BTL Transaction";
            id = $urandom;
        endfunction

        protected function string base_type_str();
            case(base_type)
                READ_REQ: return "READ_REQ";
                WRITE_REQ: return "WRITE_REQ";
                INCOMPLETE_RSP: return "INCOMPLETE_RSP";
                RSP: return "RSP";
                default: assert(0);
            endcase
        endfunction

        virtual function string sprint();
            string str = "";
            str = {str, "----------------------------------------\n"};
            str = {str, $sformatf("txn: %s,\ntype: %s,\nid: 0x%0x,\nrequester_id: 0x%0x\nsize: %0d\n",
                             name, base_type_str, id, requester_id, data_size)};
            str = {str, "----------------------------------------\n"};
            return str;
        endfunction
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
        // suggested class member
        //
        // btl::TxnMailbox txns_in;

        pure virtual function void put(Transaction txn);

        // suggested constructor
        //
        // function new();
        //     txns_in = new();
        // endfunction

        // suggested implementation of put
        //
        // task put(btl::Transaction txn);
        //     txns_in.put(txn);
        // endtask
    endclass

    typedef Subscriber SubscriberList[$];

    interface class Producer;
        // suggested class member
        //
        // btl::SubscriberList subscribers;

        pure virtual function void add_subscriber(Subscriber subscriber);

        // suggested implementation of add_subscriber
        //
        // function void add_subscriber(btl::Subscriber subscriber);
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
        const int unsigned lsb;
        const int unsigned msb;
        const int unsigned size_bits;
        const string name;
        const longint unsigned reset_value;
        const FieldAttrib attrib;
        longint unsigned value;

        function new(int unsigned lsb_in,
                     int unsigned size_bits_in,
                     string name_in,
                     longint unsigned reset_value_in,
                     FieldAttrib attrib_in);
            lsb = lsb_in;
            msb = lsb + (size_bits - 1);
            size_bits = size_bits_in;
            name = name_in;
            reset_value = reset_value_in;
            attrib = attrib_in;
            reset();
        endfunction

        function void reset();
            value = reset_value;
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
        const string name;
        const longint unsigned offset;
        const int unsigned size_bytes;
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
                for(int j = f.lsb; j <= f.msb; j++) begin
                    out[j] = f.read()[j - f.lsb];
                end
            end
            return out;
        endfunction

        function void write(longint unsigned val);
            foreach(fields[i]) begin
                Field f = fields[i];
                longint unsigned val_slice;
                for(int j = f.lsb; j <= f.msb; j++) begin
                    val_slice[j] = val[j - f.lsb];
                end
                f.write(val_slice);
            end
        endfunction
    endclass : Reg

    // index is a register offset
    typedef Reg Regs[longint unsigned];

    class AddrMap;
        longint unsigned base_addr;
        longint unsigned size_bytes;
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
            value = regs[addr].read();
            return 1;
        endfunction
    endclass : AddrMap
endpackage : btl
