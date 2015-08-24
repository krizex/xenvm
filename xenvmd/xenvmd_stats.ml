(*
 * Copyright (C) 2015 Citrix Systems Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)
open Rrdd_plugin
open Threadext
open Lwt
open Log
module D = Debug.Make(struct let name = "xenvmd_stats" end)

let phys_util () =
  let open Lvm in
  let size_of_lv_in_extents lv =
    List.map Lv.Segment.to_allocation lv.Lv.segments
    |> List.fold_left Pv.Allocator.merge []
    |> Pv.Allocator.size in
  let t =
    VolumeManager.read (fun x -> return x) >>= fun vg ->
    let bytes_of_extents = Int64.(mul (mul vg.Vg.extent_size 512L)) in
    Vg.LVs.bindings vg.Vg.lvs
    |> List.map (fun (_, lv) -> size_of_lv_in_extents lv)
    |> List.map bytes_of_extents
    |> List.fold_left Int64.add 0L
    |> return in
  Lwt_main.run t

let generate_stats owner =
  let phys_util_ds =
    Rrd.SR owner,
    Ds.ds_make
      ~name:"physical_utilisation"
      ~description:(Printf.sprintf "Physical uitilisation of SR %s" owner)
      ~value:(Rrd.VT_Int64 (phys_util ()))
      ~ty:Rrd.Gauge
      ~default:true
      ~min:0.0
      ~units:"B"
      ()
  in
  [phys_util_ds]

let reporter_cache : Reporter.t option ref = ref None
let reporter_m = Mutex.create ()

(* xenvmd currently exports just 1 datasource; a single page will suffice *)
let shared_page_count = 1

let start owner =
  Mutex.execute reporter_m (fun () ->
    match !reporter_cache with
    | Some _ -> ()
    | None ->
      let reporter =
        info "Starting RRDD reporter";
        Reporter.start_async
          (module D : Debug.DEBUG)
          ~uid:(Printf.sprintf "xenvmd-%d-stats" (Unix.getpid ()))
          ~neg_shift:0.5
          ~target:(Reporter.Local shared_page_count)
          ~protocol:Rrd_interface.V2
          ~dss_f:(fun () -> generate_stats owner)
      in
      reporter_cache := (Some reporter))

let stop () =
  Mutex.execute reporter_m (fun () ->
    match !reporter_cache with
    | None -> ()
    | Some reporter ->
      begin
        info "Stopping RRDD reporter";
        Reporter.cancel reporter;
        reporter_cache := None
      end)
