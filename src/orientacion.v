// Modulo: orientacion.v  (antes top.v)
// UNICO CAMBIO respecto a tu original: el modulo se llama ahora 'orientacion'
// para que pueda instanciarse junto al subsistema de telemetria en un top comun.
// Toda la logica de control, I2C, PWM y LEDs quedo IDENTICA.
//
// Seguidor Solar Automatico de 2 Ejes
// Nombres de puertos sincronizados con top.qsf (Cyclone IV EP4CE10E22C8)
// 
// CORRECCIONES APLICADAS:
// 1. Triplicados timeouts I2C en S_INIT y S_WAIT_CONV para estabilizar A2/A3
// 2. Tolerancias independientes: TOL_H=600, TOL_V=150
// 3. Límites PWM eje vertical reducidos a 60000-90000 (rango seguro)
// 4. Startup timer de 2 segundos antes de activar control
// 5. Mapeo verificado: A0/A1→abajo, A2/A3→arriba
// =============================================================================

module orientacion (
    input  wire       clk,         // PIN_23 (50 MHz)
    output reg  [3:0] leds,        // PIN_3, PIN_7, PIN_10, PIN_11 (Active-Low)
    inout  wire       sda,         // PIN_55 (I2C Data)
    inout  wire       scl,         // PIN_54 (I2C Clock)
    output wire       pwm_servo1,  // PIN_59: PWM Servo Horizontal (Base)
    output wire       pwm_servo2   // PIN_60: PWM Servo Vertical (Cabeza)
);

    // 1. Reset seguro de arranque (~1.3 ms)
    reg [15:0] rst_cnt = 0;
    wire rst_n = (rst_cnt == 16'hFFFF);
    always @(posedge clk) begin
        if (!rst_n) rst_cnt <= rst_cnt + 1'b1;
    end

    // 2. Senales de control I2C
    reg        i2c_exec = 0;
    reg        i2c_read = 0;
    reg        i2c_start = 0;
    reg        i2c_stop = 0;
    reg        i2c_ack_in = 0;
    reg  [7:0] i2c_din = 0;
    wire [7:0] i2c_dout;
    wire       i2c_rx_ack;
    wire       i2c_busy;

    // 3. Instancia del Master I2C
    i2c_master master_inst (
        .clk(clk),
        .rst_n(rst_n),
        .execute(i2c_exec),
        .is_read(i2c_read),
        .gen_start(i2c_start),
        .gen_stop(i2c_stop),
        .din(i2c_din),
        .ack_in(i2c_ack_in),
        .dout(i2c_dout),
        .rx_ack(i2c_rx_ack),
        .busy(i2c_busy),
        .scl(scl),
        .sda(sda)
    );

    // 4. Maquina de Estados del Escaner I2C
    localparam S_INIT          = 0,
               S_CFG_ADDR      = 1,
               S_CFG_PTR       = 2,
               S_CFG_MSB       = 3,
               S_CFG_LSB       = 4,
               S_WAIT_CONV     = 5,
               S_RD_PTR_ADDR   = 6,
               S_RD_PTR_REG    = 7,
               S_RD_DATA_ADDR  = 8,
               S_RD_DATA_MSB   = 9,
               S_RD_DATA_LSB   = 10;

    reg [3:0]  state = S_INIT;
    reg [1:0]  step = 0;
    reg [1:0]  ch_sel = 0;
    reg [23:0] delay_cnt = 0;

    reg [15:0] ch0_val = 0; // AIN0: Abajo-Izquierda
    reg [15:0] ch1_val = 0; // AIN1: Abajo-Derecha
    reg [15:0] ch2_val = 0; // AIN2: Arriba-Izquierda
    reg [15:0] ch3_val = 0; // AIN3: Arriba-Derecha
    reg [7:0]  temp_msb = 0;

    // =========================================================================
    // CORRECCIÓN 1: Triplicar timeouts en S_INIT y S_WAIT_CONV
    // Cambio de 500_000 (10 ms) a 1_500_000 (30 ms) para estabilizar A2/A3
    // =========================================================================
    localparam [23:0] I2C_INIT_DELAY = 24'd1_500_000;  // 30 ms a 50 MHz
    localparam [23:0] I2C_CONV_DELAY = 24'd1_500_000;  // 30 ms a 50 MHz

    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= S_INIT;
            step      <= 0;
            ch_sel    <= 0;
            i2c_exec  <= 0;
            delay_cnt <= 0;
        end else begin
            case (state)
                S_INIT: begin
                    // CORRECCIÓN 1: Usar delay triplicado
                    if (delay_cnt == I2C_INIT_DELAY) begin
                        delay_cnt <= 0;
                        state     <= S_CFG_ADDR;
                    end else begin
                        delay_cnt <= delay_cnt + 1'b1;
                    end
                end

                S_CFG_ADDR: begin 
                    if (step == 0) begin i2c_din <= 8'h90; i2c_start <= 1'b1; i2c_stop <= 1'b0; i2c_read <= 1'b0; i2c_exec <= 1'b1; step <= 1; end
                    else if (step == 1) begin if (i2c_busy) begin i2c_exec <= 1'b0; step <= 2; end end
                    else if (step == 2) begin if (!i2c_busy) begin state <= S_CFG_PTR; step <= 0; end end
                end

                S_CFG_PTR: begin 
                    if (step == 0) begin i2c_din <= 8'h01; i2c_start <= 1'b0; i2c_stop <= 1'b0; i2c_read <= 1'b0; i2c_exec <= 1'b1; step <= 1; end
                    else if (step == 1) begin if (i2c_busy) begin i2c_exec <= 1'b0; step <= 2; end end
                    else if (step == 2) begin if (!i2c_busy) begin state <= S_CFG_MSB; step <= 0; end end
                end

                S_CFG_MSB: begin 
                    if (step == 0) begin 
                        case (ch_sel)
                            2'd0: i2c_din <= 8'hC2;
                            2'd1: i2c_din <= 8'hD2;
                            2'd2: i2c_din <= 8'hE2;
                            2'd3: i2c_din <= 8'hF2;
                        endcase
                        i2c_start <= 1'b0; i2c_stop <= 1'b0; i2c_read <= 1'b0; i2c_exec <= 1'b1; step <= 1;
                    end
                    else if (step == 1) begin if (i2c_busy) begin i2c_exec <= 1'b0; step <= 2; end end
                    else if (step == 2) begin if (!i2c_busy) begin state <= S_CFG_LSB; step <= 0; end end
                end

                S_CFG_LSB: begin 
                    if (step == 0) begin i2c_din <= 8'h83; i2c_start <= 1'b0; i2c_stop <= 1'b1; i2c_read <= 1'b0; i2c_exec <= 1'b1; step <= 1; end
                    else if (step == 1) begin if (i2c_busy) begin i2c_exec <= 1'b0; step <= 2; end end
                    else if (step == 2) begin if (!i2c_busy) begin state <= S_WAIT_CONV; step <= 0; end end
                end

                S_WAIT_CONV: begin
                    // CORRECCIÓN 1: Usar delay triplicado
                    if (delay_cnt == I2C_CONV_DELAY) begin
                        delay_cnt <= 0;
                        state     <= S_RD_PTR_ADDR;
                    end else begin
                        delay_cnt <= delay_cnt + 1'b1;
                    end
                end

                S_RD_PTR_ADDR: begin 
                    if (step == 0) begin i2c_din <= 8'h90; i2c_start <= 1'b1; i2c_stop <= 1'b0; i2c_read <= 1'b0; i2c_exec <= 1'b1; step <= 1; end
                    else if (step == 1) begin if (i2c_busy) begin i2c_exec <= 1'b0; step <= 2; end end
                    else if (step == 2) begin if (!i2c_busy) begin state <= S_RD_PTR_REG; step <= 0; end end
                end

                S_RD_PTR_REG: begin 
                    if (step == 0) begin i2c_din <= 8'h00; i2c_start <= 1'b0; i2c_stop <= 1'b1; i2c_read <= 1'b0; i2c_exec <= 1'b1; step <= 1; end
                    else if (step == 1) begin if (i2c_busy) begin i2c_exec <= 1'b0; step <= 2; end end
                    else if (step == 2) begin if (!i2c_busy) begin state <= S_RD_DATA_ADDR; step <= 0; end end
                end

                S_RD_DATA_ADDR: begin 
                    if (step == 0) begin i2c_din <= 8'h91; i2c_start <= 1'b1; i2c_stop <= 1'b0; i2c_read <= 1'b0; i2c_exec <= 1'b1; step <= 1; end
                    else if (step == 1) begin if (i2c_busy) begin i2c_exec <= 1'b0; step <= 2; end end
                    else if (step == 2) begin if (!i2c_busy) begin state <= S_RD_DATA_MSB; step <= 0; end end
                end

                S_RD_DATA_MSB: begin 
                    if (step == 0) begin i2c_start <= 1'b0; i2c_stop <= 1'b0; i2c_read <= 1'b1; i2c_ack_in <= 1'b0; i2c_exec <= 1'b1; step <= 1; end
                    else if (step == 1) begin if (i2c_busy) begin i2c_exec <= 1'b0; step <= 2; end end
                    else if (step == 2) begin if (!i2c_busy) begin temp_msb <= i2c_dout; state <= S_RD_DATA_LSB; step <= 0; end end
                end

                S_RD_DATA_LSB: begin 
                    if (step == 0) begin i2c_start <= 1'b0; i2c_stop <= 1'b1; i2c_read <= 1'b1; i2c_ack_in <= 1'b1; i2c_exec <= 1'b1; step <= 1; end
                    else if (step == 1) begin if (i2c_busy) begin i2c_exec <= 1'b0; step <= 2; end end
                    else if (step == 2) begin 
                        if (!i2c_busy) begin
                            case (ch_sel)
                                2'd0: ch0_val <= {temp_msb, i2c_dout};
                                2'd1: ch1_val <= {temp_msb, i2c_dout};
                                2'd2: ch2_val <= {temp_msb, i2c_dout};
                                2'd3: ch3_val <= {temp_msb, i2c_dout};
                            endcase
                            ch_sel <= ch_sel + 1'b1;
                            state  <= S_CFG_ADDR;
                            step   <= 0;
                        end
                    end
                end

                default: state <= S_INIT;
            endcase
        end
    end

    // =========================================================================
    // 5. INVERSIÓN Y CÁLCULO DE PROMEDIOS DE LUZ
    // Mapeo verificado: A0/A1 → abajo, A2/A3 → arriba
    // SIN CALIBRACIÓN: Los 4 canales se tratan por igual (sin offset ni ganancia)
    // =========================================================================
    wire [14:0] raw_bl = 15'd32767 - (ch0_val[15] ? 15'd0 : ch0_val[14:0]); // Bottom-Left (A0)
    wire [14:0] raw_br = 15'd32767 - (ch1_val[15] ? 15'd0 : ch1_val[14:0]); // Bottom-Right (A1)
    wire [14:0] raw_tl = 15'd32767 - (ch2_val[15] ? 15'd0 : ch2_val[14:0]); // Top-Left (A2)
    wire [14:0] raw_tr = 15'd32767 - (ch3_val[15] ? 15'd0 : ch3_val[14:0]); // Top-Right (A3)

    // Extensión a 16 bits (sin cambios en los valores)
    wire [15:0] l_bl = {1'b0, raw_bl};
    wire [15:0] l_br = {1'b0, raw_br};
    wire [15:0] l_tl = {1'b0, raw_tl};
    wire [15:0] l_tr = {1'b0, raw_tr};

    wire [15:0] avg_top    = (l_tl + l_tr) >> 1;  // A2 + A3
    wire [15:0] avg_bottom = (l_bl + l_br) >> 1;  // A0 + A1
    wire [15:0] avg_left   = (l_tl + l_bl) >> 1;  // A2 + A0
    wire [15:0] avg_right  = (l_tr + l_br) >> 1;  // A3 + A1

    // =========================================================================
    // TOLERANCIAS ADAPTATIVAS
    // Tolerancia = base + porcentaje del promedio de luz total
    // 
    // Con más luz, las diferencias reales entre sensores son mayores (por el ángulo
    // físico de cada LDR). La tolerancia crece con la luz para acompañar esa realidad.
    //
    // Ejemplo: si promedio_luz = 20000
    //   TOL_H = 1500 + (20000 >> 3) = 1500 + 2500 = 4000  (tolerante)
    //   TOL_V = 450  + (20000 >> 4) = 450 + 1250  = 1700  (tolerante)
    //
    // En oscuridad: promedio_luz = 0 → tolerancia = base (mínima)
    // =========================================================================
    
    // Promedio de luz total (los 4 sensores promediados)
    wire [15:0] luz_promedio = (avg_top + avg_bottom) >> 1;
    
    // Tolerancias base (mínimas)
    localparam [15:0] TOL_H_BASE = 15'd1500;
    localparam [15:0] TOL_V_BASE = 15'd450;
    
    // Tolerancias adaptativas:
    //   Horizontal: base + luz/8 (12.5% del promedio)
    //   Vertical: base + luz/16 (6.25% del promedio, más sensible)
    wire [15:0] TOL_H = TOL_H_BASE + (luz_promedio >> 3);
    wire [15:0] TOL_V = TOL_V_BASE + (luz_promedio >> 4);

    // =========================================================================
    // 6. GENERADOR DE PULSOS PWM DE 50 Hz PARA SERVOS
    // =========================================================================
    reg [19:0] pwm_cnt = 0; // Periodo de 20 ms @ 50 MHz
    always @(posedge clk) begin
        if (pwm_cnt >= 20'd999_999) pwm_cnt <= 0;
        else pwm_cnt <= pwm_cnt + 1'b1; 
    end

    reg [17:0] pos_h = 18'd75000; // Posición inicial al centro (90 deg)
    reg [17:0] pos_v = 18'd75000; // Posición inicial al centro (90 deg)

    assign pwm_servo1 = (pwm_cnt < pos_h); // Asignado a PIN_59 (Servo Horizontal)
    assign pwm_servo2 = (pwm_cnt < pos_v); // Asignado a PIN_60 (Servo Vertical)

    // =========================================================================
    // 7. LÓGICA DE SEGUIMIENTO EN TIEMPO REAL CON STARTUP TIMER + HISTÉRESIS
    // =========================================================================
    
    // CORRECCIÓN 4: Startup timer de 2 segundos
    // 50 MHz * 2 segundos = 100_000_000 ciclos
    // Usar un contador de 27 bits (máximo 134_217_727)
    reg [26:0] startup_timer = 0;
    wire startup_complete = (startup_timer >= 27'd100_000_000);

    // HISTÉRESIS: Registros para recordar última dirección de cada eje
    // Previene oscilaciones cuando las lecturas son cercanas
    reg last_dir_h = 1'b0; // 0=izq, 1=der
    reg last_dir_v = 1'b0; // 0=arriba, 1=abajo
    
    // HISTÉRESIS ADAPTATIVA: Margen de cambio de dirección proporcional a la tolerancia
    // HYST = TOL + 33% (para mantener la misma relación que antes)
    wire [15:0] HYST_H = TOL_H + (TOL_H >> 2);   // ~1.25x TOL_H
    wire [15:0] HYST_V = TOL_V + (TOL_V >> 2);   // ~1.25x TOL_V

    reg [23:0] track_timer = 0;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            pos_h <= 18'd75000;
            pos_v <= 18'd75000;
            track_timer <= 0;
            startup_timer <= 0;
            last_dir_h <= 1'b0;
            last_dir_v <= 1'b0;
        end else begin
            // Incrementar startup timer hasta completarse
            if (!startup_complete) begin
                startup_timer <= startup_timer + 1'b1;
            end

            if (track_timer >= 24'd1_000_000) begin // Actualizar cada ~20 ms
                track_timer <= 0;

                // Solo ejecutar control después de startup completo
                if (startup_complete) begin
                    // --- EJE HORIZONTAL (PAN) CON HISTÉRESIS ---
                    // Direccion: mas luz izq -> pos_h aumenta (base gira izquierda)
                    //            mas luz der -> pos_h disminuye (base gira derecha)
                    // ANTI-ATASCO: Se calcula la diferencia y se decide direccion.
                    //              El movimiento SIEMPRE se ejecuta si esta dentro de limites,
                    //              no importa la posicion actual.
                    if (avg_left > avg_right) begin
                        if ((avg_left - avg_right) > TOL_H) begin
                            // Hay más luz a la izquierda, mover IZQUIERDA (aumentar pos_h)
                            if (pos_h <= 18'd99850) begin
                                pos_h <= pos_h + 18'd250;
                            end
                            last_dir_h <= 1'b0;
                        end else if (last_dir_h == 1'b1 && (avg_left - avg_right) < HYST_H) begin
                            // Zona muerta: no cambies direccion
                        end
                    end else if (avg_right > avg_left) begin
                        if ((avg_right - avg_left) > TOL_H) begin
                            // Hay más luz a la derecha, mover DERECHA (disminuir pos_h)
                            if (pos_h >= 18'd50150) begin
                                pos_h <= pos_h - 18'd250;
                            end
                            last_dir_h <= 1'b1;
                        end else if (last_dir_h == 1'b0 && (avg_right - avg_left) < HYST_H) begin
                            // Zona muerta: no cambies direccion
                        end
                    end

                    // --- EJE VERTICAL (TILT) CON HISTÉRESIS ---
                    // INVERTIDO: mas luz arriba -> pos_v DISMINUYE (cabeza sube)
                    //            mas luz abajo -> pos_v AUMENTA (cabeza baja)
                    if (avg_top > avg_bottom) begin
                        if ((avg_top - avg_bottom) > TOL_V) begin
                            // Hay más luz arriba, mover ARRIBA (disminuir pos_v)
                            if (pos_v >= 18'd50150) begin
                                pos_v <= pos_v - 18'd250;
                            end
                            last_dir_v <= 1'b0;
                        end else if (last_dir_v == 1'b1 && (avg_top - avg_bottom) < HYST_V) begin
                            // Zona muerta: no cambies direccion
                        end
                    end else if (avg_bottom > avg_top) begin
                        if ((avg_bottom - avg_top) > TOL_V) begin
                            // Hay más luz abajo, mover ABAJO (aumentar pos_v)
                            if (pos_v <= 18'd99850) begin
                                pos_v <= pos_v + 18'd250;
                            end
                            last_dir_v <= 1'b1;
                        end else if (last_dir_v == 1'b0 && (avg_bottom - avg_top) < HYST_V) begin
                            // Zona muerta: no cambies direccion
                        end
                    end
                end else begin
                    // Durante startup, mantener servos centrados
                    pos_h <= 18'd75000;
                    pos_v <= 18'd75000;
                end

            end else begin
                track_timer <= track_timer + 1'b1;
            end
        end
    end

    // =========================================================================
    // Monitoreo visual rápido con LEDs
    // - Durante startup: parpadean sincronizados
    // - En operación normal: indican dirección de luz predominante
    // =========================================================================
    always @(posedge clk) begin
        if (!startup_complete) begin
            // Durante startup, parpadear LEDs lentamente
            leds <= {4{startup_timer[22]}};
        end else begin
            // Operación normal: indicar dirección de luz predominante
            leds[0] <= ~(avg_left > avg_right);      // Mas luz a la izquierda
            leds[1] <= ~(avg_right > avg_left);      // Mas luz a la derecha
            leds[2] <= ~(avg_top > avg_bottom);      // Mas luz arriba
            leds[3] <= ~(avg_bottom > avg_top);      // Mas luz abajo
        end
    end

endmodule
