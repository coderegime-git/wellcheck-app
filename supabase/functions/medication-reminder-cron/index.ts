import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async () => {

  try {

    const supabase = createClient(
      Deno.env.get("PROJECT_URL")!,
      Deno.env.get("SERVICE_ROLE_KEY")!
    );

    const now = new Date();
    const oneMinuteAgo =
      new Date(
        now.getTime() - 60000
      );

    console.log(
      "==== MEDICATION CRON START ===="
    );

    console.log(
      "Current UTC:",
      now.toISOString()
    );

    const {
      data: meds,
      error
    } = await supabase
      .from("medications")
      .select("*")
      .eq("is_active", true)
      .eq("reminder_sent", false)
      .not("scheduled_at","is",null)
      .neq("recurrence","as_needed")
      .lte(
        "scheduled_at",
        now.toISOString()
      )
      .gte(
        "scheduled_at",
        oneMinuteAgo.toISOString()
      );

    if(error) throw error;

    console.log(
      "Found:",
      meds?.length
    );

    for(
      const med of meds ?? []
    ){

      try{

        console.log(
          "Sending reminder:",
          med.medication_name
        );

        const pushRes =
          await supabase.functions.invoke(
            "push-router",
            {
              body:{
                target_user_id:
                  med.assigned_to,

                title:
                  "💊 Medication Reminder",

                body:
                  `Time to take ${med.medication_name}`,

                action:
                  "medication_reminder",
              }
            }
          );

        console.log(
          "Push:",
          pushRes
        );

        if(
          pushRes.error
        ){
          continue;
        }

        let nextDate =
          new Date(
            med.scheduled_at
          );

        switch(
          med.recurrence
        ){

          case "daily":

            nextDate.setDate(
              nextDate.getDate()+1
            );

            break;

          case "every_other_day":

            nextDate.setDate(
              nextDate.getDate()+2
            );

            break;

          case "weekly":

            const days =
            (med.days_of_week ?? [])
            .sort(
              (a:number,b:number)=>
              a-b
            );

            if(
              days.length===0
            ){

              nextDate.setDate(
                nextDate.getDate()+7
              );

            }else{

              const currentDay=
                nextDate.getDay();

              let found=null;

              for(
                const d of days
              ){

                if(
                  d>currentDay
                ){
                  found=d;
                  break;
                }

              }

              if(
                found===null
              ){

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

            continue;
        }

        await supabase
          .from("medications")
          .update({

            scheduled_at:
              nextDate.toISOString(),

            reminder_sent:false,

            reminder_sent_at:
              new Date()
              .toISOString()

          })
          .eq(
            "id",
            med.id
          );

        console.log(
          "Updated next schedule:",
          nextDate.toISOString()
        );

      }catch(e){

        console.log(
          "Medication reminder error:",
          e
        );
      }

    }

    return new Response(
      JSON.stringify({
        success:true,
        sent:
          meds?.length ?? 0
      }),
      {
        headers:{
          "Content-Type":
          "application/json"
        }
      }
    );

  }catch(e){

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