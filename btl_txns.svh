typedef enum {
    READ_REQ,
    WRITE_REQ,
    INCOMPLETE_RSP,
    RSP
} BaseTxnType;

class Transaction extends ResponseTracker;
    BaseTxnType base_type;
    Value src_id;
    Value dest_id;
    Value tag;
    Address address;
    ByteQ data;
    // number of bytes
    int unsigned data_size;
    string origin;

    function new(BaseTxnType type_in);
        base_type = type_in;
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

    virtual function string sprint_delimiter();
        return "----------------------------------------";
    endfunction

    // This is the function you want to override in your sub classes
    // of Transaction
    virtual function string sprint_body();
        string str = "";
        str = {str, "type: ", base_type_str, "\n"};
        str = {str, "origin: ", origin, "\n"};
        str = {str, $sformatf("src_id: %0d\n", src_id)};
        str = {str, $sformatf("dest_id: %0d\n", dest_id)};
        str = {str, $sformatf("address: 0x%0x\n", address)};
        str = {str, $sformatf("data size: %0d\n", data_size)};
        str = {str, $sformatf("data bytes: %p\n", data)};
        if(data.size() <= 8) begin
            str = {str, $sformatf("data: 0x%0x\n",
                                  byteq_to_value(data))};
        end
        return str;
    endfunction

    virtual function string sprint();
        string str;
        str = {sprint_delimiter, "\n"};
        str = {str, sprint_body()};
        str = {str, sprint_delimiter};
        return str;
    endfunction

    // Copies data from all missing responses to this transaction's
    // data member then deletes its missing_responses list.  Assumes
    // no INCOMPLETE_RSP transactions are in the missing_responses
    // list.
    function void rsp_complete();
        base_type = btl::RSP;
        foreach(missing_responses[i]) begin
            assert(missing_responses[i].base_type != INCOMPLETE_RSP);
            data = {data, missing_responses[i].data};
        end
        missing_responses.delete();
    endfunction
endclass : Transaction
