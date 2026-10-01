module led(
    input [1:0] en,
    output pl_led1,
    output pl_led2
);

assign pl_led1 = en[0];
assign pl_led2 = en[1];

endmodule