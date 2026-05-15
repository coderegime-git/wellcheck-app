import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async () => {
  try {
    const supabase = createClient(
      Deno.env.get("PROJECT_URL")!,
      Deno.env.get("SERVICE_ROLE_KEY")!
    );

    const now = new Date().toISOString();

    console.log("Current UTC:", now);

    const { data: schedules, error } =
      await supabase
        .from("checkin_schedules")
        .select("*")
        .eq("is_active", true)
        .eq("is_completed", false)
        .eq("reminder_sent", false)
        .lte("scheduled_at", now);

    if (error) throw error;

    console.log(
      "Schedules found:",
      schedules?.length
    );

    for (const schedule of schedules ?? []) {

      console.log(
        "Processing:",
        schedule.id
      );

      const pushRes =
        await supabase.functions.invoke(
          "push-router",
          {
            body: {
              target_user_id:
                schedule.assigned_user_id,

              title:
                "⏰ Check-In Reminder",

              body:
                "It's time to complete your check-in.",

              action:
                "checkin_reminder",

              schedule,
            },
          }
        );

      console.log(
        "Push response:",
        pushRes
      );

      if (!pushRes.error) {

        let nextDate =
          new Date(
            schedule.scheduled_at
          );

        switch (
          schedule.recurrence
        ) {

          case "daily":

            nextDate.setDate(
              nextDate.getDate() + 1
            );

            break;


          case "every_other_day":

            nextDate.setDate(
              nextDate.getDate() + 2
            );

            break;


          case "weekly":

            const days =
              (schedule.days_of_week ?? [])
              .sort(
                (a:number,b:number)=>
                  a-b
              );

            if(days.length===0){

              nextDate.setDate(
                nextDate.getDate()+7
              );

            }else{

              const currentDay =
                nextDate.getDay();

              let found=null;

              for(const d of days){

                if(d>currentDay){

                  found=d;

                  break;
                }
              }

              if(found===null){

                found=
                  days[0]+7;
              }

              nextDate.setDate(
                nextDate.getDate()+
                (
                  found-currentDay
                )
              );
            }

            break;


          case "monthly":

            nextDate.setMonth(
              nextDate.getMonth()+1
            );

            break;


          default:

            // one-time schedule

            await supabase
              .from(
                "checkin_schedules"
              )
              .update({

                reminder_sent:true,

                reminder_sent_at:
                  new Date()
                    .toISOString(),

              })
              .eq(
                "id",
                schedule.id
              );

            continue;
        }


        console.log(
          "Next occurrence:",
          nextDate.toISOString()
        );

        await supabase
          .from(
            "checkin_schedules"
          )
          .update({

            scheduled_at:
              nextDate.toISOString(),

            reminder_sent:false,

            reminder_sent_at:null,

            is_completed:false,

            status:"pending",

          })
          .eq(
            "id",
            schedule.id
          );
      }
    }

    return new Response(
      JSON.stringify({
        success:true,
        sent:
          schedules?.length ?? 0
      }),
      {
        headers:{
          "Content-Type":
          "application/json"
        }
      }
    );

  } catch(e){

    console.log(
      "ERROR:",
      e
    );

    return new Response(
      JSON.stringify({
        error:e.message
      }),
      {
        status:500
      }
    );
  }
});