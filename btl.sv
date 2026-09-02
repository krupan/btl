// B Testbench Library (much simpler than UVM)
package btl;
    typedef longint unsigned Value;
    typedef longint unsigned Address;
    typedef byte unsigned ByteQ[$];
    typedef Value ValueQ[$];
    typedef Address AddressQ[$];
    typedef string StringQ[$];
    let max(a,b) = (a > b) ? a : b;
    let min(a,b) = (a < b) ? a : b;

    typedef enum {
        READ_REQ,
        WRITE_REQ,
        INCOMPLETE_RSP,
        RSP
    } BaseTxnType;

    function Value byteq_to_value(ByteQ data);
        return {data[7], data[6], data[5], data[4],
                data[3], data[2], data[1], data[0]};
    endfunction

    function ByteQ value_to_byteq(Value value);
        for(int i = 0; i < 8; i++) begin
            value_to_byteq.push_back(value[i*8 +: 8]);
        end
    endfunction

    `include "btl_response_tracker.svh"
    `include "btl_txns.svh"

    virtual class TxnIDTracker;
        bit ids_in_flight[Value];
    endclass

    virtual class Component extends ResponseTracker;
        mailbox #(Transaction) txns_in;
        Component subscribers[$];
        StringQ log_tags;

        function new(StringQ log_tags);
            this.log_tags = log_tags;
            txns_in = new();
        endfunction

        virtual function void add_subscriber(Component subscriber);
            subscribers.push_back(subscriber);
        endfunction

        virtual task send_to_subscribers(Transaction txn);
            foreach(subscribers[i]) begin
                subscribers[i].put(txn);
            end
        endtask

        virtual task put(Transaction txn);
            txns_in.put(txn);
        endtask

        pure virtual task run();
    endclass

endpackage : btl
