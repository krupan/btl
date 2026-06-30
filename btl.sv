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
        ByteQ data;
        int unsigned data_size; // number of bytes
        string origin;

        // this is for INCOMPLETE_RSP transactions that need multiple
        // responses (probably of a lower-level transaction type).
        // This is a queue so we know the order of the data
        Transaction missing_responses[$];

        function new(BaseTxnType type_in);
            base_type = type_in;
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
            str = {str, "origin: ", origin, "\n"};            
            str = {str, "type: ", base_type_str, "\n"};
            str = {str, $sformatf("id: %0d\n", id)};
            str = {str, $sformatf("requester_id: %0d\n", requester_id)};
            str = {str, $sformatf("data size: %0d\n", data_size)};
            str = {str, "----------------------------------------"};
            return str;
        endfunction

        virtual function void add_missing_response(Transaction rsp);
            assert(rsp.base_type == INCOMPLETE_RSP);
            missing_responses.push_back(rsp);
        endfunction

        // Outputs the index of the missing response that matches the
        // passed in responses
        virtual function bit get_missing_response(Transaction rsp, output int index);
            int results[$];
            results = missing_responses.find_index(x)
                with (x.requester_id == rsp.requester_id);
            case(results.size())
                0: return 0;
                1: begin
                    index = results[0];
                    assert(missing_responses[index].data_size == rsp.data_size);
                    return 1;
                end
                // there's a bug in the code if we get here
                default: assert(0);
            endcase
        endfunction

        // Updates the missing response that matches the passed in
        // response from INCOMPLETE_RSP to RSP, copying the data from
        // the passed in response to the missing response.  Assumes a
        // matching response exists, which can be verified by calling
        // get_missing_response first.
        virtual function void update_missing_rsp(Transaction rsp);
            int index;
            bit success = get_missing_response(rsp, index);
            assert(success);
            missing_responses[index].base_type = btl::RSP;
            missing_responses[index].data = rsp.data;
        endfunction

        // Returns 1 if there are any missing responses
        virtual function bit is_missing_responses();
            foreach(missing_responses[i]) begin
                if(missing_responses[i].base_type == btl::INCOMPLETE_RSP) begin
                    return 1;
                end
            end
            return 0;
        endfunction

        // Copies data from all missing responses to this
        // transaction's data member then deletes its
        // missing_responses list.  Assumes no INCOMPLETE_RSP
        // transactions are in the missing_responses list.
        function void rsp_complete();
            base_type = btl::RSP;
            foreach(missing_responses[i]) begin
                assert(missing_responses[i].base_type != INCOMPLETE_RSP);
                data = {data, missing_responses[i].data};
            end
            missing_responses.delete();
        endfunction
    endclass

    // These "interface" classes are feeling silly now that I'm adding
    // comments with recommended implementation.  Just make a single
    // Component class that can produce and subscribe to transactions.
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
        pure virtual task send_to_subscribers(btl::Transaction txn);

        // suggested implementation of above:
        //
        // function void add_subscriber(btl::Subscriber subscriber);
        //     subscribers.push_back(subscriber);
        // endfunction
        //
        // task send_to_subscribers(btl::Transaction txn);
        //     foreach(subscribers[i]) begin
        //         subscribers[i].put(txn);
        //     end
        // endtask
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
