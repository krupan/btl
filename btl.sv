// B Testbench Library (much simpler than UVM)
package btl;

    typedef byte unsigned ByteQ[$];
    let max(a,b) = (a > b) ? a : b;
    let min(a,b) = (a < b) ? a : b;

    `include "btl_response_tracker.svh"
    `include "btl_txns.svh"

    virtual class Component extends ResponseTracker;
        mailbox #(Transaction) txns_in;
        Component subscribers[$];

        function new();
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
