class ExampleTxnBase implements btl::Transaction;
    string my_type;
    string name;
    int id;
    function new();
        name = "txn base";
        id = $urandom;
    endfunction

    function string sprint();
        return $sformatf("id: 0x%0x, type: %s", id, my_type);
    endfunction
endclass

class TxnLowLevel extends ExampleTxnBase;
    function new();
        super.new();
        my_type = "low level";
    endfunction
endclass

class TxnMidLevel extends ExampleTxnBase;
    function new();
        super.new();
        my_type = "mid level";
    endfunction
endclass

class TxnHighLevel extends ExampleTxnBase;
    function new();
        super.new();
        my_type = "high level";
    endfunction
endclass

// Produces and Consumes TxnLowLevel
class LowLevel implements btl::Component, btl::Subscriber, btl::Producer;
    btl::SubscriberList subscribers;
    btl::TxnMailbox txns_in;

    function void add_subscriber(btl::Subscriber subscriber);
        subscribers.push_back(subscriber);
    endfunction

    function new();
        txns_in = new();
    endfunction

    function void put(btl::Transaction txn);
        txns_in.put(txn);
    endfunction

    task run();
        forever begin
            btl::Transaction txn_in;
            TxnLowLevel ll_txn_in;
            TxnLowLevel ll_txn_out;
            txns_in.get(txn_in);
            ll_txn_in = txn_in;
            $display("LowLevel got txn: ", ll_txn_in.sprint());
            if(ll_txn_in.name == "from tb top") begin
                ll_txn_out = new();
                ll_txn_out.name = "from LowLevel";
                ll_txn_out.id = ll_txn_in.id;
                foreach(subscribers[i]) begin
                    // TODO: ok, txn_in is a bad name for this method.
                    // It should probably just be "put"
                    subscribers[i].txn_in(ll_txn_out);
                end
            end
        end
    endtask
endclass

class LowToHigh implements btl::Component, btl::Subscriber, btl::Producer;
    btl::SubscriberList subscribers;
    btl::TxnMailbox txns_in;

    function void add_subscriber(btl::Subscriber subscriber);
        subscribers.push_back(subscriber);
    endfunction

    function new();
        txns_in = new();
    endfunction

    function void put(btl::Transaction txn);
        txns_in.put(txn);
    endfunction

    task run();
        forever begin
            TxnLowLevel txn_in;
            TxnHighLevel txn_out;
            txns_in.get(txn_in);
            $display("LowLevel got txn: ", txn_in.my_type);
            txn_out = new();
            txn_out.name = "from LowToHigh";
            txn_out.id = txn_in.id;
            foreach(subscribers[i]) begin
                subscribers[i].txn_in(txn_out);
            end
        end
    endtask
endclass

class HighToLow implements btl::Component, btl::Subscriber, btl::Producer;
    btl::SubscriberList subscribers;
    btl::TxnMailbox txns_in;

    function void add_subscriber(btl::Subscriber subscriber);
        subscribers.push_back(subscriber);
    endfunction

    function new();
        txns_in = new();
    endfunction

    function void put(btl::Transaction txn);
        txns_in.put(txn);
    endfunction

    task run();
        forever begin
            TxnHighLevel txn_in;
            TxnLowLevel txn_out;
            txns_in.get(txn_in);
            $display("LowLevel got txn: ", txn_in.my_type);
            txn_out = new();
            txn_out.name = "from HighToLow";
            txn_out.id = txn_in.id;
            foreach(subscribers[i]) begin
                subscribers[i].txn_in(txn_out);
            end
        end
    endtask
endclass

// Produces and Consumes TxnHighLevel
class HighLevel implements btl::Component, btl::Subscriber, btl::Producer;
    btl::SubscriberList subscribers;
    btl::TxnMailbox txns_in;

    function void add_subscriber(btl::Subscriber subscriber);
        subscribers.push_back(subscriber);
    endfunction

    function new();
        txns_in = new();
    endfunction

    function void put(btl::Transaction txn);
        txns_in.put(txn);
    endfunction

    task run();
        forever begin
            TxnLowLevel txn_in;
            TxnLowLevel txn_out;
            txns_in.get(txn_in);
            $display("HighLevel got txn: %s %s", txn_in.name, txn_in.my_type);
            txn_out = new();
            txn_out.name = "from HighLevel";
            txn_out.id = txn_in.id;
            foreach(subscribers[i]) begin
                subscribers[i].txn_in(txn_out);
            end
        end
    endtask
endclass

module top;
    LowLevel ll;
    LowToHigh low_to_high;
    HighToLow high_to_low;
    HighLevel hl;
    TxnLowLevel txn_ll;
    initial begin;
        txn_ll = new();
        ll = new();
        low_to_high = new();
        high_to_low = new();
        hl = new();

        ll.add_subscriber(low_to_high);
        low_to_high.add_subscriber(hl);

        hl.add_subscriber(high_to_low);
        high_to_low.add_subscriber(ll);

        fork
            low_to_high.run();
            high_to_low.run();
            hl.run();
            ll.run();
        join_none
        
        txn_ll = new();
        txn_ll.name = "from tb top";
        ll.put(txn_ll);
        
        $finish();
    end
endmodule
