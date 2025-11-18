import { ButtonDropdownProps, TopNavigation } from "@cloudscape-design/components";
import { APP_NAME } from "../common/constants";
import { useEffect, useState } from "react";
import { signOut, fetchAuthSession } from "aws-amplify/auth";

export default function GlobalHeader() {
  const [userName, setUserName] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      const session = await fetchAuthSession();

      if (!session) {
        signOut();
        return;
      }

      setUserName(session.tokens?.idToken?.payload?.email?.toString() ?? "");
    })();
  }, []);

  const onUserProfileClick = ({ detail }: { detail: ButtonDropdownProps.ItemClickDetails }) => {
    if (detail.id === "signout") {
      signOut();
    }
  };

  return (
    <div style={{ zIndex: 1002, top: 0, left: 0, right: 0, position: "fixed" }} id="awsui-top-navigation">
      <TopNavigation
        identity={{
          href: "/",
          title: APP_NAME,
        }}
        utilities={[
          {
            type: "menu-dropdown",
            text: userName ?? "",
            // description: userName ?? "",
            // iconName: "user-profile",
            onItemClick: onUserProfileClick,
            items: [
              {
                id: "signout",
                text: "Sign out",
              },
            ],
            // onItemFollow: onFollow,
          },
        ]}
      />
    </div>
  );
}
