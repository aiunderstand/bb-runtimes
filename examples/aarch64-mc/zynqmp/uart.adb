------------------------------------------------------------------------------
--                                                                          --
--                               GNAT EXAMPLE                               --
--                                                                          --
--                        Copyright (C) 2017, AdaCore                       --
--                                                                          --
-- GNAT is free software;  you can  redistribute it  and/or modify it under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 2,  or (at your option) any later ver- --
-- sion.  GNAT is distributed in the hope that it will be useful, but WITH- --
-- OUT ANY WARRANTY;  without even the  implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License --
-- for  more details.  You should have  received  a copy of the GNU General --
-- Public License  distributed with GNAT;  see file COPYING.  If not, write --
-- to  the  Free Software Foundation,  51  Franklin  Street,  Fifth  Floor, --
-- Boston, MA 02110-1301, USA.                                              --
--                                                                          --
-- As a special exception,  if other files  instantiate  generics from this --
-- unit, or you link  this unit with other files  to produce an executable, --
-- this  unit  does not  by itself cause  the resulting  executable  to  be --
-- covered  by the  GNU  General  Public  License.  This exception does not --
-- however invalidate  any other reasons why  the executable file  might be --
-- covered by the  GNU Public License.                                      --
--                                                                          --
-- GNAT was originally developed  by the GNAT team at  New York University. --
-- Extensive contributions were provided by Ada Core Technologies Inc.      --
--                                                                          --
------------------------------------------------------------------------------

with Ada.Interrupts.Names; use Ada.Interrupts.Names;
with System;               use System;
with System.Machine_Code;
pragma Warnings (Off);
with System.Text_IO;
with System.Machine_Reset;
pragma Warnings (On);
with Interfaces.AArch64;   use Interfaces.AArch64;

package body Uart is
   type UART is (UART0, UART1);

   The_UART : constant UART := UART0;

   Base : constant := (case The_UART is
                         when UART0 => 16#FF00_0000#,
                         when UART1 => 16#FF01_0000#);

   CR     : Unsigned_32
     with Address => System'To_Address (Base + 16#00#), Import, Volatile;
   IER    : Unsigned_32
     with Address => System'To_Address (Base + 16#08#), Import, Volatile;
   IDR    : Unsigned_32
     with Address => System'To_Address (Base + 16#0C#), Import, Volatile;
   IMR    : Unsigned_32
     with Address => System'To_Address (Base + 16#10#), Import, Volatile;
   ISR    : Unsigned_32
     with Address => System'To_Address (Base + 16#14#), Import, Volatile;
   RXTOUT : Unsigned_32
     with Address => System'To_Address (Base + 16#1C#), Import, Volatile;
   RXWM   : Unsigned_32
     with Address => System'To_Address (Base + 16#20#), Import, Volatile;
   SR     : Unsigned_32
     with Address => System'To_Address (Base + 16#2C#), Import, Volatile;

   type Char_Emu_Acc_Arr is array (Natural range <>) of Uart_Emu_Acc;
   protected Prot is
      pragma Interrupt_Priority (System.Interrupt_Priority'Last);

      procedure Handler;
      pragma Attach_Handler
        (Handler,
         (case The_UART is
            when UART0 => UART0_Interrupt,
            when UART1 => UART1_Interrupt));

      procedure Tx (Id : Natural; C : Character);

      procedure Init;

      procedure Register_Client (Client : Uart_Emu_Acc);
   private
      In_Meta : Boolean := False;
      Clients : Char_Emu_Acc_Arr (0 .. 7);
      Nbr_Clients : Natural := 0;
      Cur_Client : Natural := 0;
   end Prot;

   Hex_Digits : constant array (0 .. 15) of Character := "0123456789abcdef";

   procedure Log (C : Character) is
   begin
      while not System.Text_IO.Is_Tx_Ready loop
         null;
      end loop;

      System.Text_IO.Put (C);
   end Log;

   procedure Log (Item : String) is
   begin
      for J in Item'Range loop
         Log (Item (J));
      end loop;
   end Log;

   procedure Log_Line is
   begin
      if System.Text_IO.Use_Cr_Lf_For_New_Line then
         Log (ASCII.CR);
      end if;

      Log (ASCII.LF);
   end Log_Line;

   procedure Log_Hex8 (V : Unsigned_64) is
      Res : String (1 .. 16);
   begin
      for I in Res'Range loop
         Res (I) :=
           Hex_Digits (Natural (Shift_Right (V, 4 * (16 - I)) and 15));
      end loop;
      Log (Res);
   end Log_Hex8;

   procedure Log_Hex4 (V : Unsigned_32) is
      Res : String (1 .. 8);
   begin
      for I in Res'Range loop
         Res (I) :=
           Hex_Digits (Natural (Shift_Right (V, 4 * (8 - I)) and 15));
      end loop;
      Log (Res);
   end Log_Hex4;

   procedure Log_Dec (N : Natural) is
      D, R : Natural;
   begin
      if N < 10 then
         R := N;
      else
         D := N / 10;
         R := N - D * 10;
         Log_Dec (D);
      end if;
      Log (Character'Val (Character'Pos ('0') + R));
   end Log_Dec;

   protected body Prot is
      procedure Send_Char (C : Unsigned_32) is
      begin
         if Cur_Client < Nbr_Clients then
            Clients (Cur_Client).Rx_Cb (C);
         end if;
      end Send_Char;

      procedure Handler
      is
         C       : Character;
         Old_IM  : constant Unsigned_32 := IMR;
      begin
         --  Disable interrupts while receiving
         IDR := 16#3FFF#;

         while (SR and 2) = 0 loop
            --  Read character
            C := System.Text_IO.Get;

            if C = Character'Val (20) then
               --  C-t: escape character
               if not In_Meta then
                  In_Meta := True;
                  Log ("In meta: commands");
                  Log_Line;
                  Log ("C-r: reboot");
                  Log_Line;
                  Log ("C-b: send break");
                  Log_Line;
                  Log ("C-h: monitor");
                  Log_Line;
                  Log ("n: next client");
                  Log_Line;
                  Log ("r: registers");
                  Log_Line;
                  Log ("i: info");
                  Log_Line;
               else
                  Log ("exit meta mode");
                  In_Meta := False;
               end if;
            elsif In_Meta then
               In_Meta := False;

               if C = Character'Val (18) then
                  --  C-r: reboot
                  System.Machine_Reset.Stop;
               elsif C = Character'Val (2) then
                  --  C-b: send break
                  Send_Char (Char_Break);
               elsif C = Character'Val (8) then
                  --  C-h: monitor
                  System.Machine_Code.Asm ("smc #1", Volatile => True);
               elsif C = 'n' then
                  --  n: next client
                  Cur_Client := Cur_Client + 1;
                  if Cur_Client = Nbr_Clients then
                     Cur_Client := 0;
                  end if;
               elsif C = 'r' then
                  --  r: registers
                  Log ("EL2 ELR:");
                  Log_Hex8 (Get_ELR_EL2);
                  Log (", SPSR:");
                  Log_Hex4 (Get_SPSR_EL2);
                  Log (", ESR:");
                  Log_Hex4 (Get_ESR_EL2);
                  Log_Line;
               elsif C = 'i' then
                  Send_Char (Char_Info);
               else
                  Log ("Unexpected character: " & Character'Pos (C)'Img);
                  Log_Line;
               end if;
            else
               Send_Char (Character'Pos (C));
            end if;
         end loop;

         ISR := 16#3FFF#;

         --  Restore the interrupt mask
         IER := Old_IM;
      end Handler;

      procedure Tx (Id : Natural; C : Character) is
      begin
         if Id = Cur_Client then
            while not System.Text_IO.Is_Tx_Ready loop
               null;
            end loop;

            System.Text_IO.Put (C);
         end if;
      end Tx;

      procedure Init
      is
      begin
         --  Set timeout reception value
         RXTOUT := 255;

         --  Disable all interrupts
         IDR := 16#3FFF#;

         --  Set trigger to 1 character
         RXWM := 1;

         --  Enable receive trigger interrupt
         IER := IER or 2 ** 0;

      end Init;

      procedure Register_Client (Client : Uart_Emu_Acc) is
      begin
         if Nbr_Clients = Clients'Last then
            --  Number of clients exhausted.
            raise Constraint_Error;
         end if;

         --  Register
         Clients (Nbr_Clients) := Client;
         Client.Client_Id := Nbr_Clients;

         --  Current client is the last one
         Cur_Client := Nbr_Clients;

         Nbr_Clients := Nbr_Clients + 1;
      end Register_Client;
   end Prot;

   procedure Init is
   begin
      if not System.Text_IO.Initialized then
         System.Text_IO.Initialize;
      end if;

      Prot.Init;
   end Init;

   procedure Dump_Status is
   begin
      Log ("CR: ");
      Log_Hex4 (CR);
      Log_Line;
   end Dump_Status;

   procedure Tx (Uart : in out Uart_Emu_Type'Class; C : Unsigned_32) is
   begin
      if C <= 255 then
         Prot.Tx (Uart.Client_Id, Character'Val (C));
      end if;
   end Tx;

   procedure Register_Client (Uart : Uart_Emu_Acc) is
   begin
      Prot.Register_Client (Uart);
   end Register_Client;

end Uart;