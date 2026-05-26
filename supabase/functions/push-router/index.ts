// import "https://esm.sh/@supabase/functions-js/src/edge-runtime.d.ts";
// import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
// import { JWT } from "npm:google-auth-library@9";
//
// const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
// const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
//
// Deno.serve(async (req) => {
//   const corsHeaders = {
//     'Access-Control-Allow-Origin': '*',
//     'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
//   };
//
//   if (req.method === 'OPTIONS') {
//     return new Response('ok', { headers: corsHeaders });
//   }
//
//   if (req.method === 'GET') {
//     return new Response(JSON.stringify({ status: "push-router is online" }), {
//       headers: { ...corsHeaders, "Content-Type": "application/json" },
//       status: 200,
//     });
//   }
//
//   try {
//     const supabase = createClient(supabaseUrl, supabaseServiceKey);
//   //  const { target_user_id, title, body, payload, action } = await req.json();
// Deno.serve(async (req) => {
//   const corsHeaders = {
//     'Access-Control-Allow-Origin': '*',
//     'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
//   };
//
//   if (req.method === 'OPTIONS') {
//     return new Response('ok', { headers: corsHeaders });
//   }
//
//   if (req.method === 'GET') {
//     return new Response(JSON.stringify({ status: "push-router is online" }), {
//       headers: { ...corsHeaders, "Content-Type": "application/json" },
//       status: 200,
//     });
//   }
//
//   try {
//     const supabase = createClient(supabaseUrl, supabaseServiceKey);
//
//     // 👇 ✅ ADD THIS HERE
//     let requestData;
//
//     try {
//       const text = await req.text();
//
//       if (!text || text.trim() === "") {
//         return new Response(JSON.stringify({ error: "Empty body" }), {
//           status: 400,
//         });
//       }
//
//       requestData = JSON.parse(text);
//     } catch (e) {
//       return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
//         status: 400,
//       });
//     }
//
//     const { target_user_id, title, body, payload, action } = requestData;
//     // 👆 END HERE
//
//     if (!target_user_id) {
//       throw new Error("target_user_id is required");
//     }
//
//     // rest of your code...
//     if (!target_user_id) {
//       throw new Error("target_user_id is required");
//     }
//
//     const { data: profile } = await supabase
//       .from("profiles")
//       .select("fcm_token")
//       .eq("id", target_user_id)
//       .single();
//
//     if (!profile?.fcm_token) {
//       return new Response(JSON.stringify({ success: false, error: "No token" }), {
//         headers: { ...corsHeaders, "Content-Type": "application/json" },
//         status: 400,
//       });
//     }
//
//     const serviceAccountRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
//     const credentials = JSON.parse(serviceAccountRaw!);
//
//     const jwtClient = new JWT({
//       email: credentials.client_email,
//       key: credentials.private_key,
//       scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
//     });
//
//     const accessToken = await jwtClient.getAccessToken();
//
//     const message = {
//       message: {
//         token: profile.fcm_token,
//         notification: { title, body },
//         data: {
//           click_action: "FLUTTER_NOTIFICATION_CLICK",
//           action: action || "default",
//           payload: payload || ""
//         }
//       }
//     };
//
//     const fcmRes = await fetch(
//       `https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`,
//       {
//         method: 'POST',
//         headers: {
//           'Content-Type': 'application/json',
//           Authorization: `Bearer ${accessToken.token}`,
//         },
//         body: JSON.stringify(message),
//       }
//     );
//
//     const result = await fcmRes.json();
//
//     return new Response(JSON.stringify({ success: true, result }), {
//       headers: { ...corsHeaders, "Content-Type": "application/json" },
//       status: 200,
//     });
//
//   } catch (error) {
//     return new Response(JSON.stringify({ error: error.message }), {
//       headers: { "Content-Type": "application/json" },
//       status: 500,
//     });
//   }
// });

import "https://esm.sh/@supabase/functions-js/src/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { JWT } from "npm:google-auth-library@9";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

Deno.serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
  };

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method === "GET") {
    return new Response(
      JSON.stringify({ status: "push-router is online" }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  }

  try {
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // ✅ Safe JSON parsing
    let requestData;
    try {
      const text = await req.text();

      if (!text || text.trim() === "") {
        return new Response(JSON.stringify({ error: "Empty body" }), {
          status: 400,
        });
      }

      requestData = JSON.parse(text);
    } catch {
      return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
        status: 400,
      });
    }

    const { target_user_id, title, body, payload, action } = requestData;

    if (!target_user_id) {
      throw new Error("target_user_id is required");
    }

    // ✅ Get FCM token
    const { data: profile } = await supabase
      .from("profiles")
      .select("fcm_token")
      .eq("id", target_user_id)
      .single();

    if (!profile?.fcm_token) {
      return new Response(
        JSON.stringify({ success: false, error: "No token" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        }
      );
    }

    // ✅ Firebase credentials
const serviceAccountRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");

console.log("SECRET RAW (BASE64):", serviceAccountRaw?.substring(0, 50));

const decoded = atob(serviceAccountRaw!);
const credentials = JSON.parse(decoded);

    const jwtClient = new JWT({
      email: credentials.client_email,
      key: credentials.private_key,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });

    const accessToken = await jwtClient.getAccessToken();
    console.log("accessToken", accessToken);

    // ✅ Send FCM
    // const message = {
    //   message: {
    //     token: profile.fcm_token,
    //     notification: { title, body },
    //     data: {
    //       click_action: "FLUTTER_NOTIFICATION_CLICK",
    //       action: action || "default",
    //       payload: payload || "",
    //     },
    //   },
    // };
const isSos =
  action === "sos" ||
  title?.toLowerCase().includes("emergency");

const message = {
  message: {
    token: profile.fcm_token,

    notification: {
      title,
      body,
    },

    android: {
      priority: "high",
      notification: {
        channelId: isSos
          ? "sos_channel"
          : "general_channel",

        sound: isSos
          ? "sos_sound"
          : "custom_sound",

        defaultSound: false,
      },
    },

    apns: {
      payload: {
        aps: {
          sound: isSos
            ? "sos_sound.aiff"
            : "custom_sound.aiff",

          badge: 1,
        },
      },
    },

    data: {
      click_action:
        "FLUTTER_NOTIFICATION_CLICK",

      action:
        action || "default",

      payload:
        payload || "",

      sound:
        isSos
          ? "sos_sound"
          : "custom_sound",
    },
  },
};
    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken.token}`,
        },
        body: JSON.stringify(message),
      }
    );

    const result = await fcmRes.json();
    console.log("Push Notification result", result);

    return new Response(JSON.stringify({ success: true, result }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
          console.log("Push Notification error", error);

    return new Response(JSON.stringify({ error: error.message }), {
      headers: { "Content-Type": "application/json" },
      status: 500,
    });
  }
});